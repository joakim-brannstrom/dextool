if(NOT CMAKE_D_COMPILER)
    include(FindDCompiler)

    # The script currently only supports the DMD-style commandline interface
    if (NOT D_COMPILER_DMD_COMPAT)
        message(FATAL_ERROR "We currently only support building using a D compiler with a DMD-compatible commandline interface. (try 'ldmd2' or 'gdmd')")
    endif()

    set(CMAKE_D_COMPILER "${D_COMPILER}" CACHE PATH "D Compiler")
endif()

message(STATUS "Using D compiler: ${CMAKE_D_COMPILER}")

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/cmake/CMakeDCompiler.cmake.in
    ${CMAKE_PLATFORM_INFO_DIR}/CMakeDCompiler.cmake IMMEDIATE @ONLY)
set(CMAKE_D_COMPILER_ENV_VAR "D_COMPILER")
