#!/bin/sh
set -e

rdmd -unittest --main -I../source ./main.d
