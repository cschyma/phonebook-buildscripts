#!/bin/bash -x

set -e

cd "$( dirname "${BASH_SOURCE[0]}" )"

pkg=$1
ver=$2
if [ -z "$pkg" -o -z "$ver" ]; then
  echo "Usage $0 <frontend|backend> <version>"
  exit 1
fi

cd ../$pkg
rm -rf vendor *.deb

# Install all dependencies locally
echo "Checking dependencies.."
bundle install
echo "done."

echo "Running unittests.."
if [ "$pkg" = "frontend" ]; then
  echo 'No unittests for frontend available..'
elif [ "$pkg" = "backend" ]; then
  SPECS="spec/app/models/ spec/framework/persistence/memory_spec.rb"
  # Run unittests
  bundle exec rspec \
	--format RspecJunitFormatter \
	--out rspec.xml \
	$SPECS
fi
echo "done."

echo "Building debian package.."
# Build debian package
fpm -s dir \
	-t deb \
	-n "phonebook-$pkg" \
	-v $ver \
	--after-install debian/postinst.sh \
	--before-remove debian/prerm.sh \
	--exclude opt/phonebook-$pkg/.git \
	--exclude opt/phonebook-$pkg/coverage \
	--exclude opt/phonebook-$pkg/debian \
	.=/opt/phonebook-$pkg \
	./debian/init.d/phonebook-$pkg=/etc/init.d/phonebook-$pkg
echo "done."

