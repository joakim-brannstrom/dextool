#!/bin/bash

set -ex

mkdir -p build
pushd build
cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DEXTRA_TESTS=""
popd

MUTATIONS="--mutant lcr --mutant lcrb --mutant aor --mutant dcr --mutant sdl --mutant rorp"

dextool mutate analyze
dextool mutate test $MUTATIONS
dextool mutate report --style html $MUTATIONS --section tc_similarity --section tc_min_set
