#!/bin/sh
SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
rdmd -unittest -I$SCRIPT_DIR/../unit-threaded/source -I$SCRIPT_DIR/scriptlike/src/ -of$SCRIPT_DIR/.cpp_tests $SCRIPT_DIR/cpp_tests.d "$@"
