#!/bin/bash
./autobuild.sh --run_and_exit
TEST_STATUS=$?

if [[ $TEST_STATUS -ne 0 ]]; then
    echo "###################"
    echo "#### C_TEST #######"
    echo "###################"
    cat ./test/cstub_tests.log
    echo "###################"
    echo "#### CPP_TEST #####"
    echo "###################"
    cat ./test/cpp_tests.log
fi

exit $TEST_STATUS
