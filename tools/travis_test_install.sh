#!/bin/bash

set -exo pipefail

# The installation shall be to test_install_of_dextool/ containing binaries
ls test_install_of_dextool

# Test that it is exactly the expected number of binaries and libraries that are installed.
# The intent is to find a mismatch on the CI and thus force the developer to check it out
COUNT_INSTALLED=$(find test_install_of_dextool |wc -l)
EXPECTED_INSTALLED=15
if [[ "${COUNT_INSTALLED}" -ne $EXPECTED_INSTALLED ]]; then
    find test_install_of_dextool
    echo "Number of installed files and directories do not match the expected: $EXPECTED_INSTALLED"
    exit 1
fi
