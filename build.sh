#!/bin/bash
set -e

# create build if missing
test ! -d build && mkdir build

source ./config.sh

COMPILER=""
if [[ -n "$DC" ]]; then
    COMPILER="--compiler=$DC"
fi

if [[ $# -eq 0 ]]; then
    dub build $COMPILER -c debug
    dub build $COMPILER -c profile -b profile
    dub build $COMPILER -c devtool -b debug

    # release build is always from makefile
    make $DC
else
    dub $@ $COMPILER
fi
