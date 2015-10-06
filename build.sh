#!/bin/bash

# create build if missing
test ! -d build && mkdir build

if [[ -d "/usr/lib/llvm-3.6/lib" ]]; then
    export LFLAGS="-L/usr/lib/llvm-3.6/lib"
fi

if [[ -z "$LFLAGS" ]]; then
    echo "You must export the environment variable LFLAGS with suitable linker flags to allow dmd to find libclang"
    echo "Example:"
    echo 'export LFLAGS="-L/usr/lib/llvm-3.6/lib"'
    exit 1
fi

if [[ $# -eq 0 ]]; then
    dub build -c release
else
    dub $@
fi
