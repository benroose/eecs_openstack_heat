#!/bin/bash

# automated install and bootstrapping script for cfengine

# Pull Bootstap CFEngine hub var from POLICYHUB_IP environment var set by heat template
bootstrap_ip=$POLICYHUB_IP

## UNUSED FOR NOW
## Send output message to heat stack outputs and errors to stderr
# message_output="$heat_outputs_path.result"
# host_key_output="$heat_outputs_path.cf_host_key"
# error_output=" 1>&2"

host_key_filepath="/var/cfengine/ppkeys/localhost.pub"

package_prefix="cfengine-community"
# Since core installs from the community repository we dont ever need to set the package_version
package_source="https://cfengine-package-repos.s3.amazonaws.com"
#package_source="https://cfengine-repotest.s3.amazonaws.com"
TEST=false

DISTRO=""
ARCH=""
uname_arch=$(uname -i)

lsb_release="/usr/bin/lsb_release"

if $TEST; then
    run_prefix="/bin/echo "
else
    run_prefix=""
fi


function detect_distro {
  if [ -e "$lsb_release" ]; then
      DISTRO=$($lsb_release --short --id)
      RELEASE=$($lsb_release --short --release)
      return
  fi
  if [ -e "/etc/redhat-release" ]; then
      if grep "CentOS" /etc/redhat-release; then
          DISTRO="$(awk '/release/ {print $1}' /etc/redhat-release)"
          RELEASE="$(awk '/release/ {print $3}' /etc/redhat-release)"
          return
      fi
  fi
  if [ -e "/etc/SuSE-release" ]; then
      if grep "Enterprise Server 11" /etc/SuSE-release; then
          DISTRO="SUSE"
          RELEASE=$(awk '/VERSION/ {print $3}' /etc/SuSE-release).$(awk '/PATCHLEVEL/ {print $3}' /etc/SuSE-release)
          return
      fi
  fi
  if [ -e "/etc/debian_version" ]; then
      DISTRO="Debian"
      RELEASE=$(cat /etc/debian_version)
      return
  fi


  echo "Sorry I was unable to determine the distro"
  exit 1
}

function thanks {
echo "Ready to bootstrap using /var/cfengine/bin/cf-agent --bootstrap $bootstrap_ip"
}

function install_package {
# install cfengine from repo
case $DISTRO in
    Ubuntu|Debian)
        $run_prefix apt-get install -y --allow-unauthenticated cfengine-community && thanks
        ;;
    RedHatEnterpriseServer|CentOS)
        $run_prefix yum -y install cfengine-community && thanks
        ;;
    SUSE)
        $run_prefix zypper -n install cfengine-community && thanks
        ;;
    *)
        echo "Sorry I dont know how to install $package_name on $DISTRO $RELEASE"
        exit 1
        ;;
esac

# if wc_notify is defined, use heat wait condition to return success to heat template output
if [ -n "$wc_notify" ]; then
    $wc_notify --insecure --data-binary "{\"status\": \"SUCCESS\", \"reason\": \"successful CFE install\", \"data\": \"CFEngine installed on host\"}"
fi
}

function install_repo {
  case $DISTRO in
      Ubuntu|Debian)
          $run_prefix apt-get update
          $run_prefix apt-get dist-upgrade -y
          $run_prefix apt-get install -y apt-transport-https wget curl
          $run_prefix wget $package_source/pub/gpg.key -O /tmp/gpg.key || echo "unable to source gpg key from $package_source"
          $run_prefix apt-key add /tmp/gpg.key
          $run_prefix rm /tmp/gpg.key
          $run_prefix echo "deb $package_source/pub/apt/packages stable main" > /etc/apt/sources.list.d/cfengine-community.list
          $run_prefix apt-get update
          ;;

      RedHatEnterpriseServer|CentOS)
          $run_prefix yum install -y wget
          $run_prefix wget $package_source/pub/gpg.key || echo "unable to source gpg key from $package_source, perhaps you need to update your system certificates: http://serverfault.com/questions/394815/how-to-update-curl-ca-bundle-on-redhat"
          $run_prefix rpm --import gpg.key
          $run_prefix rm gpg.key
          $run_prefix cat <<EOF> /etc/yum.repos.d/cfengine-community.repo
[cfengine-repository]
name=CFEngine
baseurl=$package_source/pub/yum/\$basearch
enabled=1
gpgcheck=1
EOF
          ;;
      SUSE)
          $run_prefix yum install -y wget
          $run_prefix wget $package_source/pub/gpg.key || echo "unable to source gpg key from $package_source"
          $run_prefix rpm --import gpg.key
          $run_prefix zypper addrepo -t YUM $package_source/pub/yum/ cfengine-repository
          ;;
  esac
}

function cleanup {
    $run_prefix rm -f $package_name
}

function bootstrap_host {
# bootstrap client host to policyhub server after cfe installation
/var/cfengine/bin/cf-agent --bootstrap $bootstrap_ip
host_key_digest="$(/var/cfengine/bin/cf-key --print-digest $host_key_filepath)" 

# if wc_notify is defined, use heat wait condition to return success to heat template output
if [ -n "$wc_notify" ]; then
    $wc_notify --insecure --data-binary "{\"status\": \"SUCCESS\", \"reason\": \"successful CFE bootstrapping\", \"data\": \"Bootstrapped host to $bootstrap_ip\"}"
    $wc_notify --insecure --data-binary "{\"status\": \"SUCCESS\", \"reason\": \"host key fingerprint digest\", \"data\": \"Host cf-key digest: $host_key_digest\"}"
unset wc_notify
fi
}


##############################
# MAIN: SEQUENCE OF FUNCTIONS

detect_distro
install_repo
install_package
#cleanup
bootstrap_host
