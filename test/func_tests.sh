#!/bin/bash

DEFAULT_COMPILE_FLAGS="-std=c++03"
TOOL_BIN="../build/dextool"

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
    local outdir=$1
    local inhdr=$2
    local pre_args=$3
    local post_args=$4

    if [[ -n "$5" ]]; then
        local cflags="-- $5"
    fi

    echo -e "${C_YELLOW}=== $inhdr  ===${C_NONE}"
    local tmp="$TOOL_BIN $pre_args -d $outdir $inhdr $cflags $post_args"
    echo "$tmp"
    eval "$tmp"
}

function test_compare_code() {
    local outdir=$1
    local inhdr=$2

    local inhdr_base=$(basename ${inhdr})
    local expect_hdr="$(dirname ${inhdr})/"${inhdr_base%.h}".hpp.ref"
    local expect_impl="$(dirname ${inhdr})"/${inhdr_base%.h}".cpp.ref"

    if [[ -n "$3" ]]; then
        expect_hdr="$3"
    fi
    if [[ -n "$4" ]]; then
        expect_impl="$4"
    fi

    local out_hdr="$outdir/stub_"$(basename ${inhdr%.h})".hpp"
    local out_impl="$outdir/stub_"${inhdr_base%.h}".cpp"

    echo -e "Comparing result: ${expect_hdr}\t$PWD/${out_hdr}"
    diff -u "${expect_hdr}" "${out_hdr}"
    if [[ -e "${expect_impl}" ]]; then
        echo -e "Comparing result: ${expect_impl}\t$PWD/${out_impl}"
        diff -u "${expect_impl}" "${out_impl}"
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
