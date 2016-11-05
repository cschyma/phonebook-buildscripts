#!/bin/bash

set -e

DIR=$(pwd)

if [ -z "$1" ]; then
  usage
fi

PKG=""
if [ "$(basename $DIR)" = "phonebook-frontend" ]; then
  PKG="frontend"
elif [ "$(basename $DIR)" = "phonebook-backend" ]; then
  PKG="backend"
fi
VERSION=$(git log --pretty=format:'%h' -n 1)

function usage {
  echo "Usage $0 <clean|compile|test|package|integration-test>"
  exit 1
}

function clean {
  rm -rf vendor target
}

function compile {
  # Install all dependencies locally
  echo "Checking dependencies.."
  bundle install
  echo "done."
}

function rspec {
  bundle exec rspec \
  --format RspecJunitFormatter \
  --out target/rspec.xml \
  $SPECS
}

function test {
  echo "Running unittests.."
  if [ "$PKG" = "frontend" ]; then
    SPECS=""
  elif [ "$PKG" = "backend" ]; then
    SPECS="spec/app/models/ spec/framework/persistence/memory_spec.rb"
  fi
  rspec
  echo "done."
}

function integration-test {
  echo "Running integration-tests.."
  if [ "$PKG" = "frontend" ]; then
    SPECS=""
  elif [ "$PKG" = "backend" ]; then
    SPECS="spec/app/api_v1_spec.rb"
  fi
  rspec
  echo "done."
}

function package {
  echo "Building debian package.."
  # Build debian package
  mkdir -p $DIR/target
  cd $DIR/target
  fpm -s dir \
  	-t deb \
    -C $DIR \
  	-n "phonebook-$PKG" \
  	-v 1git${VERSION} \
  	--after-install ../debian/postinst.sh \
  	--before-remove ../debian/prerm.sh \
  	--exclude opt/phonebook-$PKG/.git \
  	--exclude opt/phonebook-$PKG/coverage \
  	--exclude opt/phonebook-$PKG/debian \
  	.=/opt/phonebook-$PKG \
  	./debian/init.d/phonebook-$PKG=/etc/init.d/phonebook-$PKG
  echo "done."
}

while [ -n "$1" ]; do
  case $1 in
    clean)
      clean
      ;;
    compile)
      compile
      ;;
    test)
      compile
      test
      ;;
    package)
      compile
      test
      package
      ;;
    integration-test)
      integration-test
      ;;
    *)
      usage
      ;;
  esac
  shift
done
