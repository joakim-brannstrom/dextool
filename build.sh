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
elif [[ ( $# -eq 1 ) && ( $1 == "debug_build" ) ]]; then
    dub build -c debug -b debug
    dub build -c plugin_ctestdouble_debug -b debug
    dub build -c plugin_cpptestdouble_debug -b debug
    dub build -c plugin_graphml_debug -b debug
    dub build -c plugin_uml_debug -b debug
elif [[ ( $# -eq 1 ) && ( $1 == "release_build" ) ]]; then
    dub build -c application
    dub build -c plugin_ctestdouble
    dub build -c plugin_cpptestdouble
    dub build -c plugin_graphml
    dub build -c plugin_uml
elif [[ ( $# -eq 1 ) && ( $1 == "make" ) ]]; then
    # release build is always from makefile
    make $DC
else
    dub $@ $COMPILER
fi
