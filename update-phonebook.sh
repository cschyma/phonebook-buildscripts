#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"

pkg=$1
ver=$2
stage=$3
suffix=$4

if [ -z "$pkg" -o -z "$ver" ]; then
  echo "Usage $0 <frontend|backend> <version> [<stage>] [<suffix>]"
  exit 1
fi
if [ -z "$stage" ]; then
  stage="pipeline"
fi
if [ ! -z "$suffix" ]; then
  suffix="-$suffix"
fi
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="default"
fi
if [ -z "$KUBECTL" ]; then
  KUBECTL="$(dirname $0)/kubectl.sh"
fi

${KUBECTL} set image --namespace="$NAMESPACE" deployment/phonebook-${pkg}${suffix} phonebook-${pkg}=kube-registry:5000/phonebook-${pkg}:1git${ver}
