#!/bin/bash
cd build && make -j $(nproc) rl_test
