#!/bin/bash

name=$1

if [ -z "$name" ]; then
  echo "Usage $0 <name>"
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

$KUBECTL delete pod $name
