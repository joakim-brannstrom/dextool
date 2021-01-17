# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Compiler.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Cursor.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Diagnostic.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Eval.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/File.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Index.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/SourceLocation.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/SourceRange.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Token.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/TranslationUnit.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Util.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/Visitor.d
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/info.d
)

set(flags
    "-J${CMAKE_CURRENT_LIST_DIR}/resources -I${CMAKE_SOURCE_DIR}/libs/libclang/source -I${CMAKE_SOURCE_DIR}/vendor/mylib/source"
)

compile_d_static_lib(dextool_clang "${SRC_FILES}" "${flags}" "" "dextool_libclang;dextool_mylib")

list(APPEND SRC_FILES "${CMAKE_CURRENT_LIST_DIR}/ut_main.d")
compile_d_unittest(dextool_clang "${SRC_FILES}" "${flags}" "" "dextool_libclang;dextool_mylib")
