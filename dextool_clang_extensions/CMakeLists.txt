# vim: filetype=cmake

# the C++ library

set(dextool_cpp_clang_extension_SRC
    ${CMAKE_CURRENT_LIST_DIR}/cpp_source/binary_op.cpp
    ${CMAKE_CURRENT_LIST_DIR}/cpp_source/casestmt.cpp
    ${CMAKE_CURRENT_LIST_DIR}/cpp_source/ifstmt.cpp
    ${CMAKE_CURRENT_LIST_DIR}/cpp_source/libclang_interop.cpp
    ${CMAKE_CURRENT_LIST_DIR}/cpp_source/mccabe.cpp
)

add_library(dextool_cpp_clang_extension STATIC ${dextool_cpp_clang_extension_SRC})
set_target_properties(dextool_cpp_clang_extension PROPERTIES
    COMPILE_FLAGS "${LIBLLVM_CXX_FLAGS} -O2 -g -I${CMAKE_CURRENT_LIST_DIR}/cpp_source"
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    )

target_link_libraries(dextool_cpp_clang_extension
    -lclangFrontendTool
    -lclangRewriteFrontend
    -lclangDynamicASTMatchers
    -lclangFrontend
    -lclangASTMatchers
    -lclangParse
    -lclangSerialization
    -lclangRewrite
    -lclangSema
    -lclangEdit
    -lclangAnalysis
    -lclangAST
    -lclangLex
    -lclangBasic)
target_link_libraries(dextool_cpp_clang_extension ${LIBLLVM_LIBS})

# the D library
set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/clang_extensions/package.d
    )

set(flags
    "-I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/libclang"
    )

compile_d_static_lib(dextool_clang_extensions
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_cpp_clang_extension;dextool_clang;dextool_libclang")
