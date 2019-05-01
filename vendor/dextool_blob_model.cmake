# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/blob_model/source/blob_model/*.d
)

compile_d_static_lib(dextool_blob_model "${SRC_FILES}" "" "" "")
