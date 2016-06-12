#!/bin/bash

# source ./config.sh
export LFLAG_CLANG_LIB=":libclang-3.7.so.1"
export LFLAG_CLANG_PATH="-Llib/"

if [[ "$DC" == "dmd" ]]; then
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
    make $DC
elif [[ "$DC" == "ldc2" ]]; then
    set -e
    ./build.sh
    make $DC
else
    echo "Compiler not set or supported"
    exit 1
fi
