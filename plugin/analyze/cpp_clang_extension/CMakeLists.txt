set(dextool_clang_extension_SRC
    ${CMAKE_CURRENT_LIST_DIR}/src/mccabe.cpp
)

add_library(dextool_clang_extension STATIC ${dextool_clang_extension_SRC})
set_target_properties(dextool_clang_extension PROPERTIES
    COMPILE_FLAGS "${LIBLLVM_CXX_FLAGS} -O0 -g -I${CMAKE_CURRENT_LIST_DIR}/src"
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    )

target_link_libraries(dextool_clang_extension -lclangFrontendTool -lclangRewriteFrontend -lclangDynamicASTMatchers -lclangFrontend -lclangASTMatchers -lclangParse -lclangSerialization -lclangRewrite -lclangSema -lclangEdit -lclangAnalysis -lclangAST -lclangLex -lclangBasic)
