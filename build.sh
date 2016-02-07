#!/bin/bash
set -e

# create build if missing
test ! -d build && mkdir build

if [[ -n "$LFLAGS" ]]; then
    echo "Using user env flag"
elif [[ -d "/usr/lib/llvm-3.7/lib" ]]; then
    export LFLAGS="-L/usr/lib/llvm-3.7/lib"
elif [[ -d "/usr/lib/llvm-3.6/lib" ]]; then
    export LFLAGS="-L/usr/lib/llvm-3.6/lib"
elif [[ -d "/usr/lib64/llvm" ]]; then
    export LFLAGS="-L/usr/lib64/llvm"
fi

if [[ -n "$LFLAGS" ]]; then
    echo "LFLAGS=$LFLAGS"
else
    echo "You must export the environment variable LFLAGS with suitable linker flags to allow dmd to find libclang.so.1"
    echo "Example:"
    echo 'export LFLAGS="-L/usr/lib/llvm-3.6/lib"'
    exit 1
fi

if [[ $# -eq 0 ]]; then
    dub build -c release -b release
    dub build -c debug
    dub build -c profile -b profile
    dub build -c devtool -b debug
else
    dub $@
fi
