#!/bin/bash

namespace=$1
label=$2
status=$3
timeout=$4

if [ -z "$namespace" -o -z "$label" -o -z "$status" -o -z "$timeout" ]; then
  echo "Usage $0 <namespace> <label> <status> <timeout>"
  exit 1
fi
if [ -z "$KUBECTL" ]; then
  KUBECTL="$(which kubectl)"
  if [ -z "$KUBECTL" ]; then
    KUBECTL="${WORKSPACE}/../kube/kubectl"
  fi
fi

i=0
EC=1
until [ $EC -eq 0 -o $i -ge $timeout ]; do
  current_stati=$(${KUBECTL} describe pod --namespace=$namespace -l $label | grep "Status:" | awk '{print $2}')
  current_stati=$(echo $current_stati  | sed -e "s;\n; ;g")
  echo "Waiting for pod $label to be $status, current stati are: ${current_stati}"
  for current_status in $current_stati; do
    if [ "$current_status" = "$status" ]; then
      EC=0
      break
    else
      EC=1
    fi
  done
  ((i++))
  sleep 1
done
[ $EC -eq 0 ] || exit 1
