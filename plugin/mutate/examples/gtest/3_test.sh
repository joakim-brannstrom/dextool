#!/bin/bash

cd googletest

# Run the mutation testing:
dextool mutate test --mutant lcr
