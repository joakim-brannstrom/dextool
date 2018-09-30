#!/bin/bash

cd googletest
# reset the repos files in case the mutation testing where interrupted and left
# a mutated file behind
git checkout .

# Generate a database of all mutation points:
dextool mutate analyze
