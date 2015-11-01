#!/bin/sh
SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
if [ -z "$DMD" ]; then
	DMD=dmd
fi
# RDMD isn't built-in on travis-ci's LDC/GDC
$DMD -debug -g -I$SCRIPT_DIR/../src $SCRIPT_DIR/../src/**/*.d $SCRIPT_DIR/../src/scriptlike/**/*.d -of$SCRIPT_DIR/.testExample $SCRIPT_DIR/testExample.d && $SCRIPT_DIR/.testExample "$@"

TEST_STATUS=$?
rm $SCRIPT_DIR/.o -f
exit $TEST_STATUS
