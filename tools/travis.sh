#!/bin/bash

set -exo pipefail

export ROOT=$PWD

if [[ "$DC" == "dmd" ]]; then
    echo "ok"
elif [[ "$DC" == "ldc2" ]]; then
    echo "ok"
else
    echo "Compiler (\$DC) not set or supported"
    exit 1
fi

PARALLEL=$(nproc)

./tools/travis_install_dep.d
SQLITE3="-L$ROOT/sqlite_src -lsqlite3"

mkdir build

if [[ "${DEXTOOL_BUILD}" == "DebugCov" ]]; then
    pushd build
    cmake -DTEST_WITH_COV=ON -DCMAKE_BUILD_TYPE=Debug -DBUILD_TEST=ON -DSQLITE3_LIB="${SQLITE3}" ..
    make all -j$PARALLEL
    make check -j$PARALLEL
    make check_integration -j$PARALLEL
    popd

    if [[ "$DC" == "dmd" ]]; then
        # Copy coverage data so codecov finds it
        # Coverage is only generated when the dmd compiler is used so must ensure that
        # the command always passes. Therefore a "|| true"
        # The coverage files are copied to the project root to allow codecov to find
        # them.
        set +e
        cp -- build/coverage/*.lst . || true
        ls
        set -e

        # upload
        bash <(curl -s https://codecov.io/bash)
    fi
elif [[ "${DEXTOOL_BUILD}" == "Debug" ]]; then
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Debug -DBUILD_TEST=ON -DSQLITE3_LIB="${SQLITE3}" ..
    make all -j$PARALLEL
    make check -j$PARALLEL
    make check_integration -j$PARALLEL
    popd
elif [[ "${DEXTOOL_BUILD}" == "Release" ]]; then
    # Assuming that the tests for release do NOT need to be reran.
    pushd build
    cmake -DBUILD_DOC=${BUILD_DOC} -DCMAKE_INSTALL_PREFIX=$ROOT/test_install_of_dextool -DCMAKE_BUILD_TYPE=Release -DSQLITE3_LIB="${SQLITE3}" ..
    make all -j$PARALLEL

    # Testing the install target because it has had problems before
    make install
    popd

    ./tools/travis_test_install.sh
else
    echo "\$DEXTOOL_BUILD not set"
    exit 1
fi
