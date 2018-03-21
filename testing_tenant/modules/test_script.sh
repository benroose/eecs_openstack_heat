#!/bin/bash

# testing script for wc_notify

# Pull Bootstap CFEngine hub var from POLICYHUB_IP environment var set by heat template
bootstrap_ip=$POLICYHUB_IP

# set testing var!
testing="successful push to wc_notify data"

apt-get update
apt-get install -y curl

echo "wc_notify var: $wc_notify"
echo "testing var: $testing"

# if wc_notify is defined, use heat wait condition to return success to heat template output
if [ -n "$wc_notify" ]; then
    wc_output='{"status": "SUCCESS", "reason": "successful CFE bootstrapping", "data": "Would have ootstrapped host to $bootstrap_ip"}'
    $wc_notify --insecure --data-binary "$wc_output"
    wc_output='"'
    $wc_notify --insecure --data-binary "{\"status\": \"SUCCESS\", \"reason\": \"host key fingerprint digest\", \"data\": \"testing var push: $testing\"}"
unset wc_notify
fi

echo "wc_notify var: $wc_notify"
