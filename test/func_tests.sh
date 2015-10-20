#!/bin/bash

DEFAULT_COMPILE_FLAGS="-std=c++03"
TOOL_BIN="$(readlink -f ../build/dextool-debug)"

function check_status() {
    CHECK_STATUS_RVAL=$?
    MSG=$1
    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
    else
        echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    fi
}

function test_compile_code() {
    local outdir=$1
    local inclpath=$2
    local impl=$3
    local main=$4
    local flags=$5

    echo -e "${C_YELLOW}=== Compile $impl  ===${C_NONE}"
    local tmp="g++ $flags -g -o $outdir/binary -I$outdir $inclpath $impl $main"
    echo "$tmp"
    eval "$tmp"
    "$outdir"/binary
}

function test_gen_code() {
    local outdir=$(readlink -f $1)
    local inhdr=$2
    local pre_args=$3
    local post_args=$4

    if [[ -n "$5" ]]; then
        local cflags="-- $5"
    fi

    echo -e "${C_YELLOW}=== $inhdr  ===${C_NONE}"
    local tmp="$TOOL_BIN $pre_args --out $outdir $inhdr $cflags $post_args"
    echo "$tmp"
    eval "$tmp"
}

function test_compare_code() {
    local hdr_ref=$1
    local hdr_out=$2
    local impl_ref=$3
    local impl_out=$4
    local glob_ref=$5
    local glob_out=$6
    local gmock_ref=$7
    local gmock_out=$8

    if [[ -e "${hdr_ref}" ]]; then
        echo -e "Comparing result: ${hdr_ref}\t$PWD/${hdr_out}"
        diff -u "${hdr_ref}" "${hdr_out}"
    fi

    if [[ -e "${impl_ref}" ]]; then
        echo -e "Comparing result: ${impl_ref}\t$PWD/${impl_out}"
        diff -u "${impl_ref}" "${impl_out}"
    fi

    if [[ -e "${glob_ref}" ]]; then
        echo -e "Comparing result: ${glob_ref}\t$PWD/${glob_out}"
        diff -u "${glob_ref}" "${glob_out}"
    fi

    if [[ -e "${gmock_ref}" ]]; then
        echo -e "Comparing result: ${gmock_ref}\t$PWD/${gmock_out}"
        diff -u "${gmock_ref}" "${gmock_out}"
    fi
}

function setup_test_env() {
    OUTDIR="outdata"
    if [[ ! -d "$OUTDIR" ]]; then
        mkdir "$OUTDIR"
    fi
}

function clean_test_env() {
    set +e
    rm "$OUTDIR"/*
    set -e
}

function teardown_test_env() {
    rm -r "$OUTDIR"
}
