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

    string(REPLACE "${input_}" ";" " " result)
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
        COMMAND cp --reflink=auto ${name} ${CMAKE_BINARY_DIR}/
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
# Add a named executable that depends on libraries, built from source and is a
# test with name NAME.
# It do NOT add the test to be ran when cross compiling.
#   NAME        - Target name for the executable
#   CXX_FLAGS   - Compiler flags to build source with.
#   SRC         - List of a source file or many quoted and separated by ;
#   LIBS        - List of a library or many quoted and separated by ; to link with
function(add_test_from_source_with_flags name d_flags src libs)
    add_exe_with_flags(${name} "-unittest ${d_flags}" "${src}" "${libs}" ${ARGN})
    add_test(ut_${name} ${name})
endfunction()

#=============================================================================#
# [PUBLIC]
# Add a named executable that depends on libraries, built from source and is a
# test with name NAME.
#   NAME        - Target name for the executable
#   SRC         - List of a source file or many quoted and separated by ;
#   LIBS        - List of a library or many quoted and separated by ; to link with
function(add_test_from_source name src libs)
    add_test_from_source_with_flags(${name} "" "${src}" "${libs}" ${ARGN})
endfunction()

