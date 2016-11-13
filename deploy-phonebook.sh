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
  KUBECTL="./kubectl.sh"
fi

if ${KUBECTL} describe deployment --namespace="$NAMESPACE" phonebook-${pkg}${suffix} > /dev/null 2>&1; then
  bash update-phonebook.sh $pkg $ver $stage $suffix
else
  sed -e "s;__IMG_VERSION__;1git$ver;" \
    -e "s;__STAGE__;$stage;g" \
    -e "s;__SUFFIX__;$suffix;g" \
    -e "s;__NAMESPACE__;$NAMESPACE;g" \
    yamls/deployment-phonebook-${pkg}.yaml \
    | ${KUBECTL} create -f -
fi

if ! ${KUBECTL} describe service --namespace="$NAMESPACE" phonebook-${pkg}${suffix} > /dev/null 2>&1; then
  sed -e "s;__IMG_VERSION__;1git$ver;" \
    -e "s;__STAGE__;$stage;g" \
    -e "s;__SUFFIX__;$suffix;g" \
    -e "s;__NAMESPACE__;$NAMESPACE;g" \
    yamls/service-phonebook-${pkg}.yaml \
    | ${KUBECTL} create -f -
fi
