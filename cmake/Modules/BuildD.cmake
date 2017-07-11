#=============================================================================#
# [PUBLIC]
# Build a D program.
# It is added as a named executable that depends on the supplied libraries.
#   name        - Target name for the executable
#   input_d     - List of a source file or many quoted and separated by ;
#   libs        - List of a library or many quoted and separated by ; to link with
function(build_d_executable name input_d compiler_args linker_args libs)
    set(dflags "${D_COMPILER_FLAGS} ${DDMD_DFLAGS} ${DDMD_LFLAGS} ${compiler_args}")
    set(lflags "${linker_args}")
    conv_to_proper_args(dflags "${dflags}")
    conv_to_proper_args(lflags "${lflags}")

    set(object_file ${CMAKE_CURRENT_BINARY_DIR}/${name}${CMAKE_CXX_OUTPUT_EXTENSION})
    compile_d_module("${input_d}" "${dflags}" ${object_file})
    add_executable(${name} ${object_file})

    set_target_properties(${name} PROPERTIES
        LINKER_LANGUAGE D
        COMPILE_FLAGS ""
        LINK_FLAGS "${lflags}"
        )

    # link libraries to executable
    foreach (lib "${libs}")
        target_link_libraries(${name} ${lib})
    endforeach()
endfunction()

#=============================================================================#
# [PRIVATE]
# Compiles the given D module into an object file.
#   name        - Target name for the executable
#   input_d     - List of a source file or many quoted and separated by ;
function(compile_d_module input_d d_flags output_o)
    separate_arguments(d_flags UNIX_COMMAND "${d_flags}")

    add_custom_command(
        OUTPUT ${output_o}
        COMMAND ${CMAKE_D_COMPILER} -of${output_o} ${d_flags} -c ${input_d}
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        DEPENDS ${input_d}
    )
endfunction()

#=============================================================================#
# [PUBLIC]
# Build a static library of D code.
# It is added as a named library that depends on the supplied libraries.
#   name        - Target name for the executable
#   input_d     - List of a source file or many quoted and separated by ;
#   libs        - List of a library or many quoted and separated by ; to link with
function(compile_d_static_lib name input_d compiler_args linker_args libs)
    set(dflags "${D_COMPILER_FLAGS} ${DDMD_DFLAGS} ${DDMD_LFLAGS} ${compiler_args}")
    set(lflags "${linker_args}")
    conv_to_proper_args(dflags "${dflags}")
    conv_to_proper_args(lflags "${lflags}")

    set(obj_file "${CMAKE_CURRENT_BINARY_DIR}/${name}${CMAKE_CXX_OUTPUT_EXTENSION}")
    compile_d_module("${input_d}" "${dflags}" "${obj_file}")

    add_library(${name} STATIC ${obj_file})
    set_target_properties(
        ${name} PROPERTIES
        LINKER_LANGUAGE D
        OUTPUT_NAME                 ${name}
        ARCHIVE_OUTPUT_DIRECTORY    ${CMAKE_CURRENT_BINARY_DIR}/
        LIBRARY_OUTPUT_DIRECTORY    ${CMAKE_CURRENT_BINARY_DIR}/
        RUNTIME_OUTPUT_DIRECTORY    ${CMAKE_CURRENT_BINARY_DIR}/
        COMPILE_FLAGS               ""
        LINK_FLAGS                  "${lflags}"
    )

    # link libraries to executable
    foreach (lib "${libs}")
        target_link_libraries(${name} PUBLIC ${lib})
    endforeach()
endfunction()

#=============================================================================#
# [PUBLIC]
# Build a D unittest.
# It is added as a named executable with suffix _unittest that depends on the
# supplied libraries.
#   name        - Target name for the executable
#   input_d     - List of a source file or many quoted and separated by ;
#   libs        - List of a library or many quoted and separated by ; to link with
function(compile_d_unittest name input_d compiler_args linker_args libs)
    if(NOT BUILD_TEST)
        return()
    endif()

    set(target_name ${name}_unittest)
    set(dflags "${DDMD_DFLAGS} ${compiler_args} -unittest -I${CMAKE_SOURCE_DIR}/unit-threaded/source")
    set(lflags "${linker_args}")

    if("${D_COMPILER_ID}" STREQUAL "DigitalMars")
        append("-cov" dflags)
    endif()

    conv_to_proper_args(dflags "${dflags}")
    conv_to_proper_args(lflags "${lflags}")

    # create the executable
    set(object_file ${CMAKE_CURRENT_BINARY_DIR}/${target_name}${CMAKE_CXX_OUTPUT_EXTENSION})
    compile_d_module("${input_d};${CMAKE_SOURCE_DIR}/source/test/extra_should.d" "${dflags}" ${object_file})
    add_executable(${target_name} EXCLUDE_FROM_ALL ${object_file})
    set_target_properties(${target_name} PROPERTIES
        LINKER_LANGUAGE D
        COMPILE_FLAGS ""
        LINK_FLAGS "${lflags}"
        )

    # link libraries to executable
    foreach (lib "${libs};dextool_unit_threaded")
        target_link_libraries(${target_name} ${lib})
    endforeach()

    # make cmake aware that the executable is a test
    add_test(NAME ${target_name}_
        COMMAND ${target_name}
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
    # build a dependency that mean that when check triggers it triggers a rerun
    # which in turn is dependent on the executable
    add_custom_target(${target_name}__run
        COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure -R "${target_name}_")
    add_dependencies(${target_name}__run ${target_name})
    add_dependencies(check ${target_name}__run)
endfunction()

#=============================================================================#
# [PUBLIC]
# Build a D integration test.
# It is added as a named executable with suffix _integration that depends on the
# supplied libraries.
#   name        - Target name for the executable
#   input_d     - List of a source file or many quoted and separated by ;
#   libs        - List of a library or many quoted and separated by ; to link with
function(compile_d_integration_test name input_d compiler_args linker_args libs)
    if(NOT BUILD_TEST)
        return()
    endif()

    set(target_name ${name}_integration)
    set(dflags "${DDMD_DFLAGS} ${compiler_args} -unittest -I${CMAKE_SOURCE_DIR}/unit-threaded/source -I${CMAKE_SOURCE_DIR}/test/source -I${CMAKE_SOURCE_DIR}/test/scriptlike/src")
    set(lflags "${linker_args}")

    conv_to_proper_args(dflags "${dflags}")
    conv_to_proper_args(lflags "${lflags}")

    # create the executable
    set(object_file ${CMAKE_CURRENT_BINARY_DIR}/${target_name}${CMAKE_CXX_OUTPUT_EXTENSION})
    compile_d_module("${input_d};${CMAKE_SOURCE_DIR}/source/test/extra_should.d" "${dflags}" ${object_file})
    add_executable(${target_name} EXCLUDE_FROM_ALL ${object_file})
    set_target_properties(${target_name} PROPERTIES
        LINKER_LANGUAGE D
        COMPILE_FLAGS ""
        LINK_FLAGS "${lflags}"
        )

    # link libraries to executable
    foreach (lib "${libs};dextool_unit_threaded;dextool_scriptlike;dextool_dextool_test")
        target_link_libraries(${target_name} ${lib})
    endforeach()

    # make cmake aware that the executable is a test
    add_test(NAME ${target_name}_
        COMMAND ${target_name}
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
    # build a dependency that mean that when check triggers it triggers a rerun
    # which in turn is dependent on the executable
    add_custom_target(${target_name}__run
        COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure -R "${target_name}_")
    add_dependencies(${target_name}__run ${target_name})
    add_dependencies(check_integration ${target_name}__run)
endfunction()
