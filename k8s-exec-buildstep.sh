#!/bin/bash

name=$1
cmd=$2

SVCDOMAIN='cluster.local'

if [ -z "$name" -o -z "$cmd" ]; then
  echo "Usage $0 <name> <cmd>"
  exit 1
fi
if [ -z "$KUBECTL" ]; then
  KUBECTL="$(which kubectl)"
  if [ -z "$KUBECTL" ]; then
    KUBECTL="${WORKSPACE}/../kube/kubectl"
  fi
fi
if [ -z "$KUBE_SERVER" ]; then
  KUBE_SERVER="https://kubernetes.default.svc.${SVCDOMAIN}"
fi
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="default"
fi

$KUBECTL exec -ti $name \
  --server=${KUBE_SERVER} \
  --certificate-authority="/run/secrets/kubernetes.io/serviceaccount/ca.crt" \
  --token="$(</run/secrets/kubernetes.io/serviceaccount/token)" \
  --namespace="$NAMESPACE" \
  -- bash -c "$cmd"

exitcode=$?

echo "Reading logs from pod $name:"
echo
${KUBECTL} logs --namespace="$NAMESPACE" $name

exit $exitcode
