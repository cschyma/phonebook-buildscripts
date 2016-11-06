#!/bin/bash

name=$1
shift

if [ -z "$name" -o -z "$*" ]; then
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
  KUBE_SERVER="https://kubernetes.default.svc.cluster.local"
fi
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="default"
fi

function join_by { local d=$1; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }
cmdstring='[ "'$(join_by '", "' $cmd)'" ]'

$KUBECTL exec -ti $name \
  --server=${KUBE_SERVER} \
  --certificate-authority="/run/secrets/kubernetes.io/serviceaccount/ca.crt" \
  --token="$(</run/secrets/kubernetes.io/serviceaccount/token)" \
  --namespace="$NAMESPACE" \
  -- $*

echo "Reading logs from pod $name:"
echo
${KUBECTL} logs --namespace="$NAMESPACE" $name
