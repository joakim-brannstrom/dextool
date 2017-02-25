#!/bin/sh
SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
rdmd -I~/.dub/packages/scriptlike-0.9.7/scriptlike/src/ -of$SCRIPT_DIR/.myscript $SCRIPT_DIR/myscript.d "$@"
