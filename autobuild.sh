#!/bin/bash

set -e
pushd .autobuild
dub build --skip-registry=all -b release
popd
./autobuild "$@"
