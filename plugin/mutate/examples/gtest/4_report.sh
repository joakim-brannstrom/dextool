#!/bin/bash

cd googletest
# reset the repos files in case the mutation testing where interrupted and left
# a mutated file behind
git checkout .

dextool mutate report --section tc_stat --section summary --section killed --section tc_killed_no_mutants --mutant lcr
