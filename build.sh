#!/bin/bash
set -e

# create build if missing
test ! -d build && mkdir build

source ./config.sh

if [[ $# -eq 0 ]]; then
    dub build -c release -b release
    dub build -c debug
    dub build -c profile -b profile
    dub build -c devtool -b debug
else
    dub $@
fi
