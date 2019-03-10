# - Find the dynamic lib for libclang and llvm.
#
# llvm-d version requirements:
# The identifier to set the LLVM version is defined as
# `LLVM_{MAJOR_VERSION}_{MINOR_VERSION}_{PATCH_VERSION}`, so to get LLVM
# version 3.1.0 use `LLVM_3_1_0`.
#
# The following variables are defined:
#   LIBCLANG_LDFLAGS        - flags to use when linking
#   LIBLLVM_LDFLAGS         - flags to use when linking
#   LIBLLVM_CXX_FLAGS       - the required flags to build C++ code using LLVM
#   LIBLLVM_CXX_EXTRA_FLAGS - the required flags to build C++ code using LLVM
#   LIBLLVM_FLAGS           - the required flags by llvm-d such as version
#   LIBLLVM_LIBS            - the required libraries for linking LLVM

set(LLVM_CMD_SRC ${CMAKE_SOURCE_DIR}/cmake/introspect_llvm.d)
set(LLVM_CMD ${CMAKE_BINARY_DIR}/cmake_introspect_llvm)

if(UNIX)
    separate_arguments(cmdflags UNIX_COMMAND "${D_COMPILER_FLAGS}")
else()
    separate_arguments(cmdflags WINDOWS_COMMAND "${D_COMPILER_FLAGS}")
endif()

execute_process(COMMAND ${D_COMPILER} ${cmdflags} ${LLVM_CMD_SRC} -of${LLVM_CMD}
    OUTPUT_VARIABLE llvm_config_CMD
    RESULT_VARIABLE llvm_config_CMD_status)
if (llvm_config_CMD_status)
    message(WARNING "Compiler output: ${llvm_config_CMD}")
    message(FATAL_ERROR "Unable to compile the LLVM introspector: ${D_COMPILER} ${cmdflags} ${LLVM_CMD_SRC} -of${LLVM_CMD}")
endif()

execute_process(COMMAND ${LLVM_CMD} print-llvm-config-candidates
    OUTPUT_VARIABLE llvm_config_CANDIDATES
    RESULT_VARIABLE llvm_config_CANDIDATES_status
    OUTPUT_STRIP_TRAILING_WHITESPACE)
message(STATUS "${llvm_config_CANDIDATES_status} ${llvm_config_CANDIDATES}")

execute_process(COMMAND ${LLVM_CMD} ldflags
    OUTPUT_VARIABLE llvm_config_LDFLAGS
    RESULT_VARIABLE llvm_config_LDFLAGS_status
    OUTPUT_STRIP_TRAILING_WHITESPACE)

execute_process(COMMAND ${LLVM_CMD} version
    OUTPUT_VARIABLE llvm_config_VERSION
    RESULT_VARIABLE llvm_config_VERSION_status
    OUTPUT_STRIP_TRAILING_WHITESPACE)

execute_process(COMMAND ${LLVM_CMD} cpp-flags
    OUTPUT_VARIABLE llvm_config_CPPFLAGS
    RESULT_VARIABLE llvm_config_INCLUDE_status
    OUTPUT_STRIP_TRAILING_WHITESPACE)

execute_process(COMMAND ${LLVM_CMD} libdir
    OUTPUT_VARIABLE llvm_config_LIBDIR
    RESULT_VARIABLE llvm_config_LIBDIR_status
    OUTPUT_STRIP_TRAILING_WHITESPACE)

execute_process(COMMAND ${LLVM_CMD} libs
    OUTPUT_VARIABLE llvm_config_LIBS
    RESULT_VARIABLE llvm_config_LIBS_status
    OUTPUT_STRIP_TRAILING_WHITESPACE)

execute_process(COMMAND ${LLVM_CMD} libclang-flags
    OUTPUT_VARIABLE clang_config_LDFLAGS
    RESULT_VARIABLE clang_config_LDFLAGS_status
    OUTPUT_STRIP_TRAILING_WHITESPACE)

message(STATUS "llvm-config VERSION: ${llvm_config_VERSION}")
message(STATUS "llvm-config LIBDIR: ${llvm_config_LIBDIR}")
message(STATUS "llvm-config LDFLAGS: ${llvm_config_LDFLAGS}")
message(STATUS "llvm-config INCLUDE: ${llvm_config_CPPFLAGS}")
message(STATUS "llvm-config LIBS: ${llvm_config_LIBS}")
message(STATUS "clang-config LDFLAGS: ${clang_config_LDFLAGS}")

# libCLANG ===================================================================

function(try_clang_from_user_config)
    if (LIBCLANG_LDFLAGS)
        set(LIBCLANG_CONFIG_DONE YES CACHE bool "CLANG Configuration status" FORCE)
        message("Detected user configuration of CLANG")
    endif()
endfunction()

function(try_find_libclang)
    if (clang_config_LDFLAGS_status)
        return()
    endif()

    set(LIBCLANG_LDFLAGS "${clang_config_LDFLAGS}" CACHE string "Linker flags for libclang")

    set(LIBCLANG_CONFIG_DONE YES CACHE bool "CLANG Configuration status" FORCE)
endfunction()

# === RUNNING ===

set(LIBCLANG_CONFIG_DONE NO CACHE bool "CLANG Configuration status")
try_clang_from_user_config()
if (NOT LIBCLANG_CONFIG_DONE)
    try_find_libclang()
endif()

# LLVM =======================================================================

function(try_llvm_config_find)
    if (llvm_config_LDFLAGS_status OR llvm_config_LIBS_status OR llvm_config_VERSION_status OR llvm_config_INCLUDE_status OR llvm_config_LIBDIR_status)
        return()
    endif()

    set(LIBLLVM_VERSION "${llvm_config_VERSION}" CACHE "libLLVM version" string)

    set(LIBLLVM_LIBS "${llvm_config_LIBS}" CACHE string "Linker libraries for libLLVM")

    set(LIBLLVM_LDFLAGS "${llvm_config_LDFLAGS}" CACHE string "Linker flags for libLLVM")

    set(LIBLLVM_CXX_FLAGS "${llvm_config_CPPFLAGS} ${LIBLLVM_CXX_EXTRA_FLAGS}" CACHE string "Compiler flags for C++ using LLVM")

    set(LIBLLVM_CONFIG_DONE YES CACHE bool "LLVM Configuration status" FORCE)
endfunction()

function(try_llvm_from_user_config)
    if (LIBLLVM_LDFLAGS AND LIBLLVM_FLAGS AND LIBLLVM_CXX_FLAGS)
        set(LIBLLVM_CONFIG_DONE YES CACHE bool "LLVM Configuration status" FORCE)
        message("Detected user configuration of LLVM")
    endif()
endfunction()

# === RUNNING ===

set(LIBLLVM_CONFIG_DONE NO CACHE bool "LLVM Configuration status")
try_llvm_from_user_config()
if (NOT LIBLLVM_CONFIG_DONE)
    try_llvm_config_find()
endif()

# Fixup
# Simplify to only support x86
set(LIBLLVM_TARGET "LLVM_Target_X86")
set(LIBLLVM_FLAGS "-version=${LIBLLVM_VERSION} -version=${LIBLLVM_TARGET}" CACHE string "D version flags for libLLVM")

message(STATUS "libclang config status : ${LIBCLANG_CONFIG_DONE}")
message(STATUS "libclang linker flags: ${LIBCLANG_LDFLAGS}")

message(STATUS "libLLVM config status: ${LIBLLVM_CONFIG_DONE}")
message(STATUS "libLLVM D flags: ${LIBLLVM_FLAGS}")
message(STATUS "libLLVM CXX flags: ${LIBLLVM_CXX_FLAGS}")
message(STATUS "libLLVM linker flags: ${LIBLLVM_LDFLAGS}")
message(STATUS "libLLVM libs: ${LIBLLVM_LIBS}")
