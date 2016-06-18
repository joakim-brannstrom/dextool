#!/bin/sh

set -e
dub build --skip-registry=all -c external_tests -b unittest
./.external_tests.bin "$@"
