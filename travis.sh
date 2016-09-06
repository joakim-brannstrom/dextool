#!/bin/bash

if [[ "$DC" == "dmd" ]]; then
    echo "ok"
elif [[ "$DC" == "ldc2" ]]; then
    echo "ok"
else
    echo "Compiler not set or supported"
    exit 1
fi

git clone --depth 1 -b binary_clang https://github.com/joakim-brannstrom/dextool.git lib

# source ./config.sh
export LFLAG_CLANG_LIB=":libclang.so.3.7"
export LFLAG_CLANG_PATH="-Llib/"
export LD_LIBRARY_PATH="$PWD/lib"

./autobuild.sh --run_and_exit
TEST_STATUS=$?

if [[ $TEST_STATUS -ne 0 ]]; then
    echo "#####################"
    echo "#### External #######"
    echo "#####################"
    cat ./test/external_tests.log
    exit 1
fi

set -e

./build.sh build -c debug -b debug
./build.sh build -c devtool -b debug
./build.sh make
