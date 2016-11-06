#!/bin/bash

img=$1
name=$2
cmd=$3
override_file=$4

if [ -z "$name" -o -z "$img" -o -z "$cmd" ]; then
  echo "Usage $0 <name> <image> [<cmd>] [<override-file>]"
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

[ -z "$cmd" ] && cmd="tail -f /dev/null"
[ -z "$override_file" ] && override_file="kubernetes-run-overrides.json"

function join_by { local d=$1; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }
cmdstring='[ "'$(join_by '", "' $cmd)'" ]'

$KUBECTL run $name \
  --server=${KUBE_SERVER} \
  --certificate-authority="/run/secrets/kubernetes.io/serviceaccount/ca.crt" \
  --token="$(</run/secrets/kubernetes.io/serviceaccount/token)" \
  --namespace="$NAMESPACE" \
  --image=kube-registry.kube-system.svc.cluster.local:5000/${img} \
  --restart=Never \
  --overrides="$(sed -e "s;__NAME__;$name;g" \
	-e "s;__IMAGE__;$img;g" \
	-e "s;__CMD__;$cmdstring;g" \
  -e "s;__NAMESPACE__;$NAMESPACE;g" \
	$(dirname $0)/${override_file})"

echo
bash $(dirname $0)/wait-for-pod-state.sh "app=${name}" Running 30

echo "Reading logs from pod $name:"
echo
${KUBECTL} logs --namespace="$NAMESPACE" $name
