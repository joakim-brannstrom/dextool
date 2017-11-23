# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_SOURCE_DIR}/clang/Compiler.d
    ${CMAKE_SOURCE_DIR}/clang/Cursor.d
    ${CMAKE_SOURCE_DIR}/clang/Diagnostic.d
    ${CMAKE_SOURCE_DIR}/clang/File.d
    ${CMAKE_SOURCE_DIR}/clang/Index.d
    ${CMAKE_SOURCE_DIR}/clang/info.d
    ${CMAKE_SOURCE_DIR}/clang/SourceLocation.d
    ${CMAKE_SOURCE_DIR}/clang/SourceRange.d
    ${CMAKE_SOURCE_DIR}/clang/Token.d
    ${CMAKE_SOURCE_DIR}/clang/TranslationUnit.d
    ${CMAKE_SOURCE_DIR}/clang/Type.d
    ${CMAKE_SOURCE_DIR}/clang/Util.d
    ${CMAKE_SOURCE_DIR}/clang/Visitor.d
)

set(flags
    "-J${CMAKE_SOURCE_DIR}/clang/resources -I${CMAKE_SOURCE_DIR}/libclang"
)

compile_d_static_lib(dextool_clang "${SRC_FILES}" "-dip1000 -dip25 ${flags}" "" "dextool_libclang")

list(APPEND SRC_FILES "${CMAKE_SOURCE_DIR}/clang/ut_main.d")
compile_d_unittest(dextool_clang "${SRC_FILES}" "${flags}" "" "dextool_libclang")
