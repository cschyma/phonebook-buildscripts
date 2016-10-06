#!/bin/bash

dir=$1
if [ -z "$dir" -o ! -d "$dir" ]; then
	echo "Usage: $0 <directory>"
fi

# Run integration tests
cd $dir

if [ -z "$ENDPOINT" ]; then
	export ENDPOINT="phonebook-backend"
fi

SPECS="spec/app/api_v1_spec.rb"
bundle exec rspec \
	--format RspecJunitFormatter \
	--out rspec-int.xml \
	$SPECS
