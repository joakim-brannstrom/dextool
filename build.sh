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
    dub build $COMPILER -c application -b release
    dub build $COMPILER -c debug -b debug
elif [[ ( $# -eq 1 ) && ( $1 == "make" ) ]]; then
    # release build is always from makefile
    make $DC
else
    dub $@ $COMPILER
fi
