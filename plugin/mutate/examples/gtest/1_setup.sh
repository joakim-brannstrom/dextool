#!/bin/bash

# Obtain the project you want to analyze:
git clone https://github.com/google/googletest.git

# copy the prepared configuration
# Use dextool mutate admin --init for a new project
cp .dextool_mutate.toml googletest

cp test.sh googletest
cp compile.sh googletest

cd googletest

mkdir build

pushd build
# Generate a JSON compilation database for the project
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
make -j$(nproc)
popd
