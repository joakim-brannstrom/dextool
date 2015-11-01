#!/bin/sh
SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
rdmd -I$SCRIPT_DIR/scriptlike/src/ -of$SCRIPT_DIR/.cstub_tests $SCRIPT_DIR/cstub_tests.d "$@"
