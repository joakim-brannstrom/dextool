#!/bin/sh
set -e

# rdmd -g -unittest --main -I../source ./ut2.d
dub test -- $@
