#!/bin/bash

set -e

function log_start {
  echo "####################################"
  echo "# $1"
  echo "####################################"
}

function log_end {
  echo "####################################"
  echo "# done."
  echo "####################################"
  echo
}

log_start "Stopping and disabling k8s.."
systemctl stop kubelet
systemctl disable kubelet
log_end "done."

log_start "Stopping docker.."
systemctl stop docker
log_end "done."

log_start "Preparing docker for local operation.."
cd /var/lib/docker
for dir in image containers; do
  [ -d ${dir} ] && mv ${dir} ${dir}.k8s
  [ -d ${dir}.local ] || ( mkdir ${dir}.local && chmod 700 ${dir}.local )
  [ -L ${dir} ] && rm ${dir}
  ln -s ${dir}.local ${dir}
done
log_end "done."

log_start "Disabling k8s dns.."
sed -i -e 's;^nameserver 100.64.0.10;#nameserver 100.64.0.10;' /etc/resolvconf/resolv.conf.d/head
sed -i -e 's;^nameserver 100.64.0.10;#nameserver 100.64.0.10;' /etc/resolv.conf
log_end "done."

log_start "Starting docker.."
systemctl start docker
log_end "done."
