#!/bin/bash

mkdir -p build
pushd build
cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DGTEST_DIR=../../../../vendor/fused_gmock
popd

mkdir -p build_cov
pushd build_cov
cmake .. -DGTEST_DIR=../../../../vendor/fused_gmock -DGCOV=ON
popd
