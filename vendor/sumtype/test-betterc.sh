#!/bin/sh
dmd -unittest -g -betterC -I=src -i -run test_betterc.d
