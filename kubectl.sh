#!/bin/bash
SVCDOMAIN="k8s.ws.p7-s.net"

if [ -z "$KUBECTL" ]; then
  KUBECTL="$(which kubectl)"
  if [ -z "$KUBECTL" ]; then
    KUBECTL="${WORKSPACE}/../kube/kubectl"
  fi
fi
if [ -z "$KUBE_SERVER" ]; then
  KUBE_SERVER="https://kubernetes.default.svc.${SVCDOMAIN}"
fi

${KUBECTL} \
  --server=${KUBE_SERVER} \
  --certificate-authority="/run/secrets/kubernetes.io/serviceaccount/ca.crt" \
  --token="$(</run/secrets/kubernetes.io/serviceaccount/token)" \
  $*
