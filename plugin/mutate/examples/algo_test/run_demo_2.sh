#!/bin/bash

echo "Extending with tests to kill the an ABS mutant"

set -ex

mkdir -p build
pushd build
cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DEXTRA_TESTS="-DTEST_RORP -DTEST_ABS"
popd

MUTATIONS="--mutant lcr --mutant lcrb --mutant aor --mutant dcr --mutant sdl --mutant rorp --mutant abs"

dextool mutate analyze
dextool mutate test $MUTATIONS
dextool mutate report --style html $MUTATIONS --section tc_similarity --section tc_min_set
