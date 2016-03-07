#!/bin/bash
./autobuild.sh --run_and_exit
TEST_STATUS=$?

if [[ $TEST_STATUS -ne 0 ]]; then
    echo "#####################"
    echo "#### External #######"
    echo "#####################"
    cat ./test/external_tests.log

    exit $TEST_STATUS
fi

# Test building all releases
set -e
./build.sh
