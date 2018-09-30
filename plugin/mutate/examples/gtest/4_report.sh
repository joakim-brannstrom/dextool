#!/bin/bash

cd googletest

dextool mutate report --section tc_stat --section summary --section killed --section tc_killed_no_mutants --mutant lcr
