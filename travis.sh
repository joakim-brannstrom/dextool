#!/bin/bash

export ROOT=$PWD

if [[ "$DC" == "dmd" ]]; then
    echo "ok"
elif [[ "$DC" == "ldc2" ]]; then
    echo "ok"
else
    echo "Compiler not set or supported"
    exit 1
fi

git clone --depth 1 -b binary_clang https://github.com/joakim-brannstrom/dextool.git lib

CLANG_PATH=$ROOT/lib
export LD_LIBRARY_PATH="$CLANG_PATH"

set -e

mkdir build
pushd build
cmake -DLIBCLANG_LIB_PATH=$CLANG_PATH/libclang.so.3.7 -DCMAKE_BUILD_TYPE=Debug -DBUILD_TEST=ON ..
make check -j3
make all -j3
make check_integration
popd

# Copy coverage data so codecov finds it
# Coverage is only generated when the dmd compiler is used so must ensure that
# the command always passes. Therefore a "|| true"
# The coverage files are copied to the project root to allow codecov to find
# them.
set +e
cp -- build/*.lst . || true
ls
set -e

# Ensure release build works.
# Assuming that the tests for release do NOT need to be reran.
# Testing the install target because it has had problems before
make clean
mkdir build
pushd build
cmake -DLIBCLANG_LIB_PATH=$CLANG_PATH/libclang.so.3.7 -DCMAKE_INSTALL_PREFIX=$ROOT/test_install_of_dextool ..
make all -j3
make install
popd

# The installation shall be to test_install_of_dextool/ containing binaries
ls test_install_of_dextool
