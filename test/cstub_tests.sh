#!/bin/sh

# TODO can't run tests in parallell, segfaults in escapePosixArgumentImpl.

SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
rdmd -g -unittest -I$SCRIPT_DIR/../unit-threaded/source -I$SCRIPT_DIR/scriptlike/src/ -of$SCRIPT_DIR/.cstub_tests $SCRIPT_DIR/cstub_tests.d -s "$@"
