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

log_start "Stopping docker.."
systemctl stop docker
log_end "done."

log_start "Preparing docker for k8s operation.."
cd /var/lib/docker
for dir in image containers; do
  [ -d ${dir} ] && mv ${dir} ${dir}.k8s
  [ -d ${dir}.local ] || ( mkdir ${dir}.local && chmod 700 ${dir}.local )
  [ -L ${dir} ] && rm ${dir}
  ln -s ${dir}.k8s ${dir}
done
log_end "done."

log_start "Starting docker.."
systemctl start docker
log_end "done."

log_start "Starting and enabling k8s.."
systemctl enable kubelet
systemctl start kubelet
log_end "done."

log_start "Waiting for cluster to start.."
sleep 10
while ! kubectl get pods --namespace kube-system 2>&1 | grep 'kube-dns.*3/3.*Running' > /dev/null; do
  echo -n '.'
  sleep 5;
done
echo
log_end "done."

log_start "Enabling k8s dns.."
sed -i -e 's;^#nameserver 100.64.0.10;nameserver 100.64.0.10;' /etc/resolvconf/resolv.conf.d/head
sed -i -e 's;^#nameserver 100.64.0.10;nameserver 100.64.0.10;' /etc/resolv.conf
log_end "done."
