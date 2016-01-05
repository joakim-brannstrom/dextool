#!/bin/bash

SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
rdmd -I$SCRIPT_DIR/test/scriptlike/src/ -I$SCRIPT_DIR/test/ -of$SCRIPT_DIR/.autobuild $SCRIPT_DIR/autobuild.d "$@"
