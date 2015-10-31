#!/bin/bash
set -e

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

# Test strategy.
# Stage 1. Generation.
#  - Test stub generation of increasing difficulty. The result is compared to references.
#  - Test compiling generated code with gcc. Generated binary and execute.
#  Stage 2. Distributed.
#  - Test stub generation when the interface to stub is recursive and in more than one file.
#  Stage 3. Functionality.
#  - Implement tests that uses the generated stubs.

function check_status() {
    CHECK_STATUS_RVAL=$?
    MSG=$1
    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
    else
        echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    fi
}

exit 0
