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
TOOL_BIN="$TOOL_BIN cstub"

echo "Stage 1"
for sourcef in testdata/cstub/stage_1/*.h; do
    inhdr_base=$(basename ${sourcef})
    out_impl="$OUTDIR/stub_"${inhdr_base%.h}".cpp"

    case "$sourcef" in
        *functions*)
            test_gen_code "$OUTDIR" "$sourcef" --debug ;;
        *variables*)
            test_gen_code "$OUTDIR" "$sourcef" --debug ;;
        # Test examples
        # **)
        #     test_gen_code "$OUTDIR" "$sourcef" "--debug" ;;
        # **)
        #     test_gen_code "$OUTDIR" "$sourcef" "--debug" "|& grep -i $grepper"
        # ;;
        # *)
        #     test_gen_code "$OUTDIR" "$sourcef" ;;
        *) ;;
    esac

    case "$sourcef" in
        *)
            test_compare_code "$OUTDIR" "$sourcef" ;;
    esac

    case "$sourcef" in
        *functions*)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-Wpedantic" ;;
        *variables*) ;;
        # Compare examples
        # *)
        #     test_compl_code "$OUTDIR" "-Itestdata/stage_1" "$out_impl" main1.cpp "-Wpedantic -Werror" ;;
    esac

    clean_test_env
done

teardown_test_env

exit 0
