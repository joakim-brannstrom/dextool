#!/bin/bash

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
    source ./config.sh
    make $DC
elif [[ "$DC" == "ldc2" ]]; then
    set -e
    ./build.sh
    # load config.sh after build.sh to enusre that build.sh loaded it by itself
    source ./config.sh
    make $DC
else
    echo "Compiler not set or supported"
    exit 1
fi
