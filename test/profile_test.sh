#!/bin/sh
SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
rdmd -I$SCRIPT_DIR/scriptlike/src/ -of$SCRIPT_DIR/.profile_test $SCRIPT_DIR/profile_test.d "$@"
