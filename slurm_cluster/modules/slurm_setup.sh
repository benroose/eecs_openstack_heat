#!/bin/bash
 
# Install required packages for slurm
apt-get update && apt-get -y dist-upgrade
apt-get install -y slurm-wlm nfs-kernel-server python

# Create local slurm user
useradd -m slurmuser
mkdir -p /home/slurmuser/.ssh
echo "$PUBLIC_KEY" > /home/slurmuser/.ssh/authorized_keys
echo "$PRIVATE_KEY" > /home/slurmuser/.ssh/id_rsa

# Put ssh config
cat > /home/slurmuser/.ssh/config <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF

# Get nodes IP from openstack metadata
list=$(curl http://169.254.169.254/openstack/latest/meta_data.json 2>/dev/null | python -c 'import json,sys;metadata=json.load(sys.stdin);list=json.loads(metadata.get("meta", {}).get("servers", "[]")); print tuple(map(str,list)) ')

# Remove useless chars
list=${list//[\' ()]}

# Convert string to array
IFS=',' read -r -a server_list <<< "$list"

# Select default network device 
dev=$(/sbin/ip route | awk '/default/ { print $5 }')

# Find out associated IP
my_ip=$(ip a | grep ${dev} -A1 | grep inet | awk '{print $2}' | cut -d "/" -f 1)          

# export home directory
echo "/home/ubuntu *(rw,all_squash,anonuid=1000,anongid=1000,sync,no_subtree_check)" | tee /etc/exports

# Restart NFS server
sudo systemctl restart nfs-server

# Get hostname
master_hostname=$(hostname)

# Update host file
cat >> /etc/hosts << EOF
${my_ip} ${master_hostname}
EOF

# Create slurm.conf file
cat > /etc/slurm-llnl/slurm.conf << EOF
# slurm.conf file generated during openstack cloud-init.
# Put this file on all nodes of your cluster.
# See the slurm.conf man page for more information.
#
ControlMachine=${master_hostname}
ControlAddr=${my_ip}
#
#MailProg=/bin/mail
MpiDefault=none
#MpiParams=ports=#-#
ProctrackType=proctrack/pgid
ReturnToService=1
SlurmctldPidFile=/var/run/slurm-llnl/slurmctld.pid
#SlurmctldPort=6817
SlurmdPidFile=/var/run/slurm-llnl/slurmd.pid
#SlurmdPort=6818
SlurmdSpoolDir=/var/lib/slurm-llnl/slurmd
SlurmUser=slurmuser
#SlurmdUser=root
StateSaveLocation=/var/lib/slurm-llnl/slurmctld
SwitchType=switch/none
TaskPlugin=task/none
#
#
# TIMERS
#KillWait=30
#MinJobAge=300
#SlurmctldTimeout=120
#SlurmdTimeout=300
#
#
# SCHEDULING
FastSchedule=0
SchedulerType=sched/backfill
#SchedulerPort=7321
SelectType=select/linear
#
#
# LOGGING AND ACCOUNTING
AccountingStorageType=accounting_storage/none
ClusterName=$STACK_NAME
#JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/none
#SlurmctldDebug=3
SlurmctldLogFile=/var/log/slurm-llnl/slurmctld.log
#SlurmdDebug=3
SlurmdLogFile=/var/log/slurm-llnl/slurmd.log
#
#
# COMPUTE NODES
EOF

# Add nodes IP in hosts file and update slurm.conf as well
i=-1
for item in "${server_list[@]}"
do
    ip=$(echo ${item} | cut -d "@" -f 1)
    node_hostname=$(echo ${item} | cut -d "@" -f 2)
    nbproc=$(echo ${item} | cut -d "@" -f 3)
    memory=$(echo ${item} | cut -d "@" -f 4)
    cat >> /etc/hosts << EOF
${ip} ${node_hostname}
EOF
    cat >> /etc/slurm-llnl/slurm.conf << EOF
NodeName=${node_hostname} Procs=${nbproc} RealMemory=${memory} State=IDLE
EOF
    ((i++))
done

cat >> /etc/slurm-llnl/slurm.conf << EOF
NodeName=${master_hostname} Procs=${nbproc} RealMemory=${memory} State=IDLE
PartitionName=slurm Nodes=$NODE_NAME-[0-${i}] Default=YES MaxTime=INFINITE State=UP
EOF

# Fix perms
chmod 600 /home/slurmuser/.ssh/id_rsa
chown -R slurmuser. /home/slurmuser/.ssh
chown -R slurmuser. /home/slurmuser

# Create munge secret key
# create-munge-key -r
dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key
chown munge. /etc/munge/munge.key

# Deploy settings
for item in "${server_list[@]}"
do                ip=$(echo ${item} | cut -d "@" -f 1)
    sudo -H -u slurmuser scp /etc/hosts ${ip}:/tmp/hosts
    sudo -H -u slurmuser ssh ${ip} sudo mv /tmp/hosts /etc/hosts

    sudo -H -u slurmuser scp /etc/munge/munge.key ${ip}:/tmp/munge.key
    sudo -H -u slurmuser ssh ${ip} sudo mv /tmp/munge.key /etc/munge/munge.key
    sudo -H -u slurmuser ssh ${ip} sudo chown munge. /etc/munge/munge.key
    sudo -H -u slurmuser ssh ${ip} sudo chmod 400 /etc/munge/munge.key

    sudo -H -u slurmuser scp /etc/slurm-llnl/slurm.conf ${ip}:/tmp/slurm.conf
    sudo -H -u slurmuser ssh ${ip} sudo mv /tmp/slurm.conf /etc/slurm-llnl/slurm.conf

    # Fix 
    sudo -H -u slurmuser ssh ${ip} sudo "sed -i -e \"s@ExecStart=.*@ExecStart=/usr/sbin/munged --syslog@\" /lib/systemd/system/munge.service"
    sudo -H -u slurmuser ssh ${ip} sudo systemctl daemon-reload

    sudo -H -u slurmuser ssh ${ip} sudo systemctl restart munge
    sudo -H -u slurmuser ssh ${ip} sudo systemctl restart slurmd

    sudo -H -u slurmuser ssh ${ip} "echo \"${my_ip}:/home/ubuntu    /home/ubuntu   nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0\" | sudo tee -a /etc/fstab"
    sudo -H -u slurmuser ssh ${ip} sudo mount -a
done

chmod 400 /etc/munge/munge.key

# Fix 
sudo sed -i -e "s@ExecStart=.*@ExecStart=/usr/sbin/munged --syslog@" /lib/systemd/system/munge.service
sudo systemctl daemon-reload

systemctl restart munge
systemctl restart slurmd
systemctl restart slurmctld

# Notify Heat we're done
wc_notify --insecure --data-binary '{"status": "SUCCESS"}'
