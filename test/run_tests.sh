#!/bin/bash
set -e

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

source ./func_tests.sh

# Test strategy.
# Stage 1. Generation.
#  - Test stub generation of increasing difficulty. The result is compared to references.
#  - Test compiling generated code with gcc. Generated binary and execute.
#  Stage 2. Distributed.
#  - Test stub generation when the interface to stub is recursive and in more than one file.
#  Stage 3. Functionality.
#  - Implement tests that uses the generated stubs.

setup_test_env
TOOL_BIN="$TOOL_BIN cppstub"

echo "Stage 1"
for sourcef in testdata/stage_1/*.hpp; do
    inhdr_base=$(basename ${sourcef})
    out_impl="$OUTDIR/stub_"${inhdr_base%.hpp}".cpp"

    case "$sourcef" in
        *functions*)
            test_gen_code "$OUTDIR" "$sourcef" --debug ;;
        *variables*)
            test_gen_code "$OUTDIR" "$sourcef" --debug ;;
        # *class_interface*)
        #     test_gen_code "$OUTDIR" "$sourcef" --debug ;;
        # *class_no_virtual*)
        #     test_gen_code "$OUTDIR" "$sourcef" "--func-scope=all" ;;
        # **)
        #     test_gen_code "$OUTDIR" "$sourcef" "--debug" ;;
        # **)
        #     test_gen_code "$OUTDIR" "$sourcef" "--debug" "|& grep -i $grepper"
        # ;;
        # *)
        #     test_gen_code "$OUTDIR" "$sourcef" ;;
        *)
            continue ;;
    esac

    case "$sourcef" in
        *)
            test_compare_code "$OUTDIR" "$sourcef" ;;
    esac

    case "$sourcef" in
        *functions*)
            test_compile_code_code "$OUTDIR" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
        *variables*) ;;
    #     *class_interface*)
    #         test_compl_code "$OUTDIR" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
    #     *class_inherit*)
    #         test_compl_code "$OUTDIR" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
    #     *class_in_ns*)
    #         test_compl_code "$OUTDIR" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
    #     *)
    #         test_compl_code "$OUTDIR" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic -Werror" ;;
    esac

    clean_test_env
done
exit 0

echo "Stage 2"
test_gen_code "$OUTDIR" "testdata/stage_2/case1/ifs1.hpp" "--file-scope=all"
test_compare_code "$OUTDIR" "testdata/stage_2/case1/ifs1.hpp"
test_compile_code "$OUTDIR" "-Itestdata/stage_2/case1" "$OUTDIR/stub_ifs1.cpp" "testdata/stage_2/main.cpp"

echo "Test compilator parameter with extra include path result in a correct stub"
test_gen_code "$OUTDIR" "testdata/stage_2/case2/ifs1.hpp" "--file-scope=all" "" "-Itestdata/stage_2/case2/sub"
test_compare_code "$OUTDIR" "testdata/stage_2/case2/ifs1.hpp"
test_compile_code "$OUTDIR" "-Itestdata/stage_2/case2 -Itestdata/stage_2/case2/sub" "$OUTDIR/stub_ifs1.cpp" "testdata/stage_2/main.cpp"

echo "Test limiting of stubbing to the supplied file"
test_gen_code "$OUTDIR" "testdata/stage_2/case3/ifs1.hpp" "" "" "-Itestdata/stage_2/case3/sub"
test_compare_code "$OUTDIR" "testdata/stage_2/case3/ifs1.hpp"
test_compile_code "$OUTDIR" "-Itestdata/stage_2/case3 -Itestdata/stage_2/case3/sub" "$OUTDIR/stub_ifs1.cpp" "testdata/stage_2/main.cpp"

echo "Stage 3"
test_gen_code "$OUTDIR" "testdata/stage_3/ifs1.hpp" "--file-scope=all"
test_compile_code "$OUTDIR" "-Itestdata/stage_3" "$OUTDIR/stub_ifs1.cpp" "testdata/stage_3/main.cpp"

teardown_test_env

exit 0
