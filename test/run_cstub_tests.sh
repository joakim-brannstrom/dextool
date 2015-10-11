#!/bin/bash
set -e

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

source ./func_tests.sh

# Test strategy.
# Stage 1. Generation.
#  - Test stub generation of varying difficulty. The principal is a golden file that the result is compared to.
#  - Test compiling generated code with gcc. Generated binary and execute.
# Stage 2. Distributed.
#  - Test stub generation of many files, both including and excluding.
#  Stage 3. Functionality.
#  - Implement tests that uses the generated stubs.

setup_test_env
TOOL_BIN="$TOOL_BIN ctestdouble"

echo "Stage 1"
for sourcef in testdata/cstub/stage_1/*.h; do
    inhdr_base=$(basename ${sourcef})
    out_impl="$OUTDIR/stub_"${inhdr_base%.h}".cpp"

    case "$sourcef" in
        # Test examples
        # *somefile*)
        #     test_gen_code "$OUTDIR" "$sourcef" "--debug" ;;
        # *somefile*)
        #     test_gen_code "$OUTDIR" "$sourcef" "--debug" "|& grep -i $grepper"
        # ;;
        *)
            test_gen_code "$OUTDIR" "$sourcef" "--debug" ;;
        *) ;;
    esac

    case "$sourcef" in
        *)
            test_compare_code "$OUTDIR" "$sourcef" ;;
    esac

    case "$sourcef" in
        # *functions*)
        #     test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
        # *variables*) ;;
        # Compile examples
        *)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-Wpedantic -Werror" ;;
    esac

    clean_test_env
done

echo "Stage 2"
INCLUDES="-Itestdata/cstub/stage_2 -Itestdata/cstub/stage_2/include"

for IN_SRC in testdata/cstub/stage_2/*.h; do
    inhdr_base=$(basename ${IN_SRC})
    out_impl="$OUTDIR/stub_"${inhdr_base%.h}".cpp"

    case "$IN_SRC" in
        *test1*)
            test_gen_code "$OUTDIR" "$(readlink -f $IN_SRC)" "--debug --exclude=$(readlink -f $IN_SRC)" "" "$INCLUDES"
            ;;
        *test2*)
            test_gen_code "$OUTDIR" "$(readlink -f $IN_SRC)" "--debug --exclude=$(readlink -f $IN_SRC) --exclude=testdata/cstub/stage_2/include/b.h" "" "$INCLUDES"
            ;;
        *) ;;
    esac

    test_compare_code "$OUTDIR" "$IN_SRC"
    test_compile_code "$OUTDIR" "$INCLUDES" "$out_impl" main1.cpp

    clean_test_env
done



teardown_test_env

exit 0
