#!/bin/bash

cd googletest
# reset the repos files in case the mutation testing where interrupted and left
# a mutated file behind
git checkout .

# Run the mutation testing:
dextool mutate test --mutant lcr
