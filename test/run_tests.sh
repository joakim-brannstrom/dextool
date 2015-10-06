#!/bin/bash
set -e

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

# Test strategy.
# Stage 1. Generation.
#  - Test stub generation of increasing difficulty. The result is compared to references.
#  - Test compiling generated code with gcc. Generated binary and execute.
#  Stage 2. Distributed.
#  - Test stub generation when the interface to stub is recursive and in more than one file.
#  Stage 3. Functionality.
#  - Implement tests that uses the generated stubs.

function check_status() {
    CHECK_STATUS_RVAL=$?
    MSG=$1
    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
    else
        echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    fi
}

function test_compl_code() {
    outdir=$1
    inclpath=$2
    impl=$3
    main=$4
    flags=$5

    echo -e "${C_YELLOW}=== Compile $impl  ===${C_NONE}"
    tmp="g++ -std=c++03 $flags -g -o $outdir/binary -I$outdir $inclpath $impl $main"
    echo "$tmp"
    eval "$tmp"
    "$outdir"/binary
}

function test_gen_code() {
    outdir=$1
    inhdr=$2
    pre_args=$3
    post_args=$4

    if [[ -n "$5" ]]; then
        cflags="-- $5"
    fi

    echo -e "${C_YELLOW}=== $inhdr  ===${C_NONE}"
    tmp="../build/dextool stub $pre_args -d $outdir $inhdr $cflags $post_args"
    echo "$tmp"
    eval "$tmp"
}

function test_compare_code() {
    outdir=$1
    inhdr=$2

    inhdr_base=$(basename ${inhdr})
    expect_hdr="$(dirname ${inhdr})/"${inhdr_base}".ref"
    expect_impl="$(dirname ${inhdr})"/${inhdr_base%.hpp}".cpp.ref"

    if [[ -n "$3" ]]; then
        expect_hdr="$3"
    fi
    if [[ -n "$4" ]]; then
        expect_impl="$4"
    fi

    out_hdr="$outdir/stub_"$(basename ${inhdr})
    out_impl="$outdir/stub_"${inhdr_base%.hpp}".cpp"

    # echo $out_hdr
    # cat $out_hdr
    # exit 1

    echo -e "Comparing result: ${expect_hdr}\t$PWD/${out_hdr}"
    diff -u "${expect_hdr}" "${out_hdr}"
    if [[ -e "${expect_impl}" ]]; then
        echo -e "Comparing result: ${expect_impl}\t$PWD/${out_impl}"
        diff -u "${expect_impl}" "${out_impl}"
    fi
}

outdir="outdata"
if [[ ! -d "$outdir" ]]; then
    mkdir "$outdir"
fi

echo "Stage 1"
for sourcef in testdata/stage_1/*.hpp; do
    inhdr_base=$(basename ${sourcef})
    out_impl="$outdir/stub_"${inhdr_base%.hpp}".cpp"

    case "$sourcef" in
        *functions*)
            test_gen_code "$outdir" "$sourcef" --debug ;;
        # *class_interface*)
        #     test_gen_code "$outdir" "$sourcef" --debug ;;
        # *class_no_virtual*)
        #     test_gen_code "$outdir" "$sourcef" "--func-scope=all" ;;
        # **)
        #     test_gen_code "$outdir" "$sourcef" "--debug" ;;
        # **)
        #     test_gen_code "$outdir" "$sourcef" "--debug" "|& grep -i $grepper"
        # ;;
        # *)
        #     test_gen_code "$outdir" "$sourcef" ;;
        *)
            continue ;;
    esac

    case "$sourcef" in
        *)
            test_compare_code "$outdir" "$sourcef" ;;
    esac

    case "$sourcef" in
        *functions*)
            test_compl_code "$outdir" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
    #     *class_interface*)
    #         test_compl_code "$outdir" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
    #     *class_inherit*)
    #         test_compl_code "$outdir" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
    #     *class_in_ns*)
    #         test_compl_code "$outdir" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
    #     *)
    #         test_compl_code "$outdir" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic -Werror" ;;
    esac

    set +e
    rm "$outdir"/*
    set -e
done
exit 0

echo "Stage 2"
test_gen_code "$outdir" "testdata/stage_2/case1/ifs1.hpp" "--file-scope=all"
test_compare_code "$outdir" "testdata/stage_2/case1/ifs1.hpp"
test_compl_code "$outdir" "-Itestdata/stage_2/case1" "$outdir/stub_ifs1.cpp" "testdata/stage_2/main.cpp"

echo "Test compilator parameter with extra include path result in a correct stub"
test_gen_code "$outdir" "testdata/stage_2/case2/ifs1.hpp" "--file-scope=all" "" "-Itestdata/stage_2/case2/sub"
test_compare_code "$outdir" "testdata/stage_2/case2/ifs1.hpp"
test_compl_code "$outdir" "-Itestdata/stage_2/case2 -Itestdata/stage_2/case2/sub" "$outdir/stub_ifs1.cpp" "testdata/stage_2/main.cpp"

echo "Test limiting of stubbing to the supplied file"
test_gen_code "$outdir" "testdata/stage_2/case3/ifs1.hpp" "" "" "-Itestdata/stage_2/case3/sub"
test_compare_code "$outdir" "testdata/stage_2/case3/ifs1.hpp"
test_compl_code "$outdir" "-Itestdata/stage_2/case3 -Itestdata/stage_2/case3/sub" "$outdir/stub_ifs1.cpp" "testdata/stage_2/main.cpp"

echo "Stage 3"
test_gen_code "$outdir" "testdata/stage_3/ifs1.hpp" "--file-scope=all"
test_compl_code "$outdir" "-Itestdata/stage_3" "$outdir/stub_ifs1.cpp" "testdata/stage_3/main.cpp"

rm -r "$outdir"

exit 0
