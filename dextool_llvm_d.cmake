# vim: filetype=cmake

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/llvm-d/source ${LIBLLVM_FLAGS}")

file(GLOB SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/llvm-d/source/*/*.d)
compile_d_static_lib(dextool_llvm_d "${SRC_FILES}" "${flags}" "" "")
target_link_libraries(dextool_llvm_d ${LIBLLVM_LDFLAGS})
target_link_libraries(dextool_llvm_d ${LIBLLVM_LIBS})

if (BUILD_TEST)
# the following is a nice example that can be built to test that cmake and the
# llvm installation work together.
build_d_executable(
    llvm_d_fibonacci
    "${CMAKE_CURRENT_LIST_DIR}/llvm-d/examples/fibonacci/fibonacci.d"
    "${flags}"
    ""
    "dextool_llvm_d"
    )
endif()
