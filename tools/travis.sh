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

set -e

# sqlite3
git clone --depth 1 -b sqlite_src --single-branch https://github.com/joakim-brannstrom/dextool.git sqlite_src
SQLITE3="-L$ROOT/sqlite_src -lsqlite3"

# debug build
mkdir build
pushd build
cmake -DTEST_WITH_COV=ON -DCMAKE_BUILD_TYPE=Debug -DBUILD_TEST=ON -DSQLITE3_LIB="${SQLITE3}" ..
make all -j3
make check -j3
make check_integration -j3
popd

# Copy coverage data so codecov finds it
# Coverage is only generated when the dmd compiler is used so must ensure that
# the command always passes. Therefore a "|| true"
# The coverage files are copied to the project root to allow codecov to find
# them.
set +e
cp -- build/coverage/*.lst . || true
ls
set -e

# release build

# Assuming that the tests for release do NOT need to be reran.
# Testing the install target because it has had problems before
make clean
mkdir build
pushd build
cmake -DCMAKE_INSTALL_PREFIX=$ROOT/test_install_of_dextool -DCMAKE_BUILD_TYPE=Release -DSQLITE3_LIB="${SQLITE3}" ..
make all -j3
make install
popd

# The installation shall be to test_install_of_dextool/ containing binaries
ls test_install_of_dextool
