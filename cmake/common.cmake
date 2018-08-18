#=============================================================================#
# [PUBLIC]
# Helper function
function(append value)
    foreach(variable ${ARGN})
        if(${variable} STREQUAL "")
            set(${variable} "${value}" PARENT_SCOPE)
        else()
            set(${variable} "${${variable}} ${value}" PARENT_SCOPE)
        endif()
    endforeach(variable)
endfunction()

#=============================================================================#
# [PUBLIC]
# Converts a value to a proper string of arguments for a program.
#  - Convert a list to a string separated by whitespace.
#  - Space separated arguments are cleaned out
function(conv_to_proper_args output_ input_)
    string(FIND "${input_}" ";" found_semicolon)
    if (${found_semicolon} EQUAL -1)
        return()
    endif()

    string(REPLACE ";" " " result "${input_}")
    separate_arguments(result UNIX_COMMAND "${result}")
    string(STRIP "${result}" result)

    set(output_ "${result}" PARENT_SCOPE)
endfunction()

#=============================================================================#
# [PUBLIC]
# Copy/link the target to the binary directory.
# Useful to collect all the binaries in one directory for testing purpose.
function(collect_binary_in_root name)
    add_custom_command(
        TARGET ${name}
        POST_BUILD
        COMMAND ${CMAKE_SOURCE_DIR}/tools/symlink.d ${CMAKE_CURRENT_BINARY_DIR}/${name} ${CMAKE_BINARY_DIR}/${name}
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    )
endfunction()

#=============================================================================#
# [PUBLIC]
# Print all properties of cmake (globals)
function(Print_All_Properties)
    get_cmake_property(_variableNames VARIABLES)
    foreach (_variableName ${_variableNames})
        message(STATUS "${_variableName}=${${_variableName}}")
    endforeach()
endfunction()

#=============================================================================#
# [PUBLIC]
# Print all properties of cmake associated with a directory.
# This flags are used to compile the files in the directory.
function(Print_Dir_Properties)
    get_directory_property(_variableNames DIRECTORY ${CMAKE_SOURCE_DIR} COMPILE_DEFINITIONS )
    foreach (_variableName ${_variableNames})
        message(STATUS "${_variableName}=${${_variableName}}")
    endforeach()
endfunction()

#=============================================================================#
# [PUBLIC]
# Setup environment (symlinks) for integration testing
macro(setup_integration_testing_env)
    if (BUILD_TEST)
        execute_process(
            COMMAND ${CMAKE_SOURCE_DIR}/tools/symlink.d ${CMAKE_SOURCE_DIR}/vendor/fused_gmock ${CMAKE_CURRENT_BINARY_DIR}/fused_gmock
            COMMAND ${CMAKE_SOURCE_DIR}/tools/symlink.d ${CMAKE_BINARY_DIR}/testdata ${CMAKE_CURRENT_BINARY_DIR}/testdata
            COMMAND ${CMAKE_SOURCE_DIR}/tools/symlink.d ${CMAKE_BINARY_DIR} ${CMAKE_CURRENT_BINARY_DIR}/path_to_dextool
            COMMAND ${CMAKE_SOURCE_DIR}/tools/symlink.d ${CMAKE_BINARY_DIR}/vendor/libgmock_gtest.a ${CMAKE_CURRENT_BINARY_DIR}/libgmock_gtest.a
            COMMAND ${CMAKE_SOURCE_DIR}/tools/symlink.d ${CMAKE_CURRENT_LIST_DIR}/testdata ${CMAKE_CURRENT_BINARY_DIR}/plugin_testdata
            )
    endif()
endmacro()
