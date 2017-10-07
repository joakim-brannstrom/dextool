# vim: filetype=cmake

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source -I${CMAKE_SOURCE_DIR}/llvm-d/source ${LIBLLVM_FLAGS}")

set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/ast/tree.d

    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/analysis.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/buffer.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/context.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/io.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/module_.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/llvm_io.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/package.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/types.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/util.d

    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/type/function_.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/type/struct_.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/type/type.d

    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/attribute.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/basic_block.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/constant.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/function_.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/global.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/instruction.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/metadata.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/parameter.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/phi.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/use.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/user.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/source/llvm_hiwrap/value/value.d
)

compile_d_static_lib(dextool_llvm_hiwrap "${SRC_FILES}" "${flags}" "" "dextool_llvm_d")

set(TEST_LINK_SRC
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/test/test_linking.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/test/test_utils.d
    )
compile_d_unittest(
    llvm_hiwrap_test_instantiation
    "${TEST_LINK_SRC}"
    "${flags}"
    ""
    "dextool_llvm_hiwrap"
    )

set(UT_SRC
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/test/ut_main.d
    ${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/test/test_utils.d
    )
compile_d_unittest(
    llvm_hiwrap_test
    "${UT_SRC};${SRC_FILES}"
    "${flags}"
    ""
    "dextool_llvm_hiwrap"
    )

build_d_executable(
    "llvm_cfg_viewer"
    "${CMAKE_CURRENT_LIST_DIR}/llvm_hiwrap/test/cfg_viewer.d"
    "-I${CMAKE_CURRENT_LIST_DIR}/llvm-d/source -I${CMAKE_SOURCE_DIR}/llvm_hiwrap/source"
    ""
    "dextool_llvm_hiwrap"
)
