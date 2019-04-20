#!/bin/bash

echo "Activate the ABS test that catches the bug"

set -ex

mkdir -p build
pushd build
cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DEXTRA_TESTS="-DTEST_RORP -DTEST_ABS -DTEST_ABS2 -DREAL_BUG"
popd

./build.sh
./test.sh
