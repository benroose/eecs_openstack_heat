# Introduction


# Quick start


# Parameters

The master node doesn't execute any job, if you specify count=3 then you'll have 3 workers plus one master.

For example, create a 4 nodes cluster, with a c1.large flavor :

```
openstack stack create -t slurm.yaml \
	-e lib/env.yaml \
	--parameter "count=4;flavor=c1.large;key_name=fgaudet-key;image_id=7c09f5aa-52fa-4daf-a14d-8956cde1e0f2;net_id=fgaudet-net2;name=fgaudet-slurm" slurm-stack
```

# Check the master

Get your cluster's public IP address using the stack id (see above):

`openstack stack output show b7a7092c-876c-4c19-a8d3-47cb857a0ca6 public_ip`

This command should return you something like this, with of course a real IP :
```
+--------------+--------------------------------------------+
| Property     | Value                                      |
+--------------+--------------------------------------------+
| description  | The public IP address of this mpi cluster. |
| output_key   | public_ip                                  |
| output_value | "XXX.XXX.XXX.XXX"                          |
+--------------+--------------------------------------------+
```

Then, connect to your master, using this IP you've just find out :

`ssh ubuntu@<IP>`
