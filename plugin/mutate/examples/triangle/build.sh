#!/bin/bash
set -e
MAKEFILE_DIR=$(dirname "${BASH_SOURCE[0]}")
make -f $MAKEFILE_DIR/Makefile test_triangle
