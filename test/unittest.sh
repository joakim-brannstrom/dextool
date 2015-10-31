#!/bin/sh
set -e

echo "Building tests"
dub build -b unittest

echo "Running..."
./build/dsrcgen_test
