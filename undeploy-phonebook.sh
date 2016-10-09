#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"

pkg=$1
stage=$2
suffix=$3

if [ -z "$pkg" ]; then
  echo "Usage $0 <frontend|backend> [<stage>] [<suffix>]"
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
  KUBECTL="$(which kubectl)"
  if [ -z "$KUBECTL" ]; then
    KUBECTL="${WORKSPACE}/../kube/kubectl"
  fi
fi

${KUBECTL} delete deployment --namespace="$NAMESPACE" phonebook-${pkg}${suffix}
${KUBECTL} delete service --namespace="$NAMESPACE" phonebook-${pkg}${suffix}
