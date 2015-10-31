#!/bin/bash

CMD="rdmd $PWD/unit-threaded-experimental/source/unit_threaded/gen_ut_main.d"

BASE="generator translator"

pushd source
$CMD -f ../test/ut_main.d $BASE application
$CMD -f ../test/wip_ut_main.d $BASE wipapp
popd
