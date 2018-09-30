#!/bin/bash
set -e
cd build
ctest -V -j4
