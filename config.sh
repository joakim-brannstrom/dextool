#!/bin/bash

if [[ -n "$LFLAG_CLANG_PATH" ]]; then
    echo "Using user env flag \$LFLAG_CLANG_PATH"
elif [[ -d "/usr/lib/llvm-3.9/lib" ]]; then
    export LFLAG_CLANG_PATH="-L/usr/lib/llvm-3.9/lib"
elif [[ -d "/usr/lib/llvm-3.8/lib" ]]; then
    export LFLAG_CLANG_PATH="-L/usr/lib/llvm-3.8/lib"
elif [[ -d "/usr/lib/llvm-3.7/lib" ]]; then
    export LFLAG_CLANG_PATH="-L/usr/lib/llvm-3.7/lib"
elif [[ -d "/usr/lib/llvm-3.6/lib" ]]; then
    export LFLAG_CLANG_PATH="-L/usr/lib/llvm-3.6/lib"
elif [[ -d "/usr/lib64/llvm" ]]; then
    export LFLAG_CLANG_PATH="-L/usr/lib64/llvm"
fi

if [[ -n "$LFLAG_CLANG_LIB" ]]; then
    echo "Using user env flag \$LFLAG_CLANG_LIB"
else
    export LFLAG_CLANG_LIB=":libclang.so.1"
fi

if [[ -z "$LFLAG_CLANG_PATH" ]]; then
    echo "You must export the environment variable LFLAG_CLANG_PATH with suitable linker flags to allow dmd to find libclang.so.1"
    echo "Example:"
    echo 'export LFLAG_CLANG_PATH="-L/usr/lib/llvm-3.6/lib"'
    return 1
fi

echo "LFLAG_CLANG_PATH=$LFLAG_CLANG_PATH"
echo "LFLAG_CLANG_LIB=$LFLAG_CLANG_LIB"
