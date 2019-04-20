#!/bin/bash
set -e
cd build
make test ARGS="-V"
