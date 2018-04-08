#!/bin/bash

# run the script from the root of the deXtool repo
AUTOBUILD_TOOL=tools/autobuild
AUTOBUILD_BIN=autobuild.bin

set -e
pushd $AUTOBUILD_TOOL
dub build --skip-registry=all -b release
popd

./.autobuild.bin "$@"
