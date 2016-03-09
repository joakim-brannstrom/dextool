#!/bin/sh
SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"

rdmd -g -unittest -I$SCRIPT_DIR/../unit-threaded/source -I$SCRIPT_DIR/scriptlike/src/ -of$SCRIPT_DIR/.external_tests $SCRIPT_DIR/external_main.d -s "$@"
