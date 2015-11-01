#!/bin/bash
set -e

TOOL_BIN=$(readlink -f ../build)"/dextool-profile"
if [[ $# -eq 1 ]]; then
    TOOL_BIN=$1
fi
TOOL_BIN="time $TOOL_BIN ctestdouble"

source ./func_tests.sh

# Test strategy.
#  Stage 4. Performance profiling

setup_test_env

echo "Stage 4"
echo "Profile google test"
INCLUDES="-Itestdata/stage_4/fused_gtest"
ROOT_DIR="testdata/stage_4/fused_gtest"
inhdr_base="gtest/gtest-all.cc"

test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" " --gen-pre-incl --gen-post-incl" "" "-xc++ $INCLUDES"
# test_compile_code "$OUTDIR" "$INCLUDES" "$out_impl" main1.cpp "-DTEST_INCLUDE"
show_profile_log
clean_test_env

teardown_test_env
exit 0
