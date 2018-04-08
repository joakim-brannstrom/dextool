#!/bin/bash

if [[ $# -ne 2 ]]; then
    echo "Wrong number of arguments: src dst"
    exit 1
fi

# symlinks via cmake execute_process are buggy which SOMETIMES.
# this try to be stable, always working.
# ln -sfT do NOT work on macosX.

rm -f "$2"
ln -sf "$1" "$2"
