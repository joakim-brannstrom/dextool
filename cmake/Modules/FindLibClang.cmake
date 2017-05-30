# - Find the dynamic lib for libclang.
#
# The user can during configuration time specify an extra path to search for
# libclang.so:
# USER_LIBCLANG_SEARCH_PATH
#
# The user can force a specific path by setting LIBCLANG_LIB_PATH to the
# absolute path to the dynamic lib, e.g. path/to/libclang.so
#
# The following variables are defined:
#   LIBCLANG_LIB_PATH   - full path to the dynamic library
#   LIBCLANG_LDFLAGS    - flags to use when linking

if(LIBCLANG_LIB_PATH AND LIBCLANG_LDFLAGS)
    message(FATAL_ERROR " this shouldn't happen, libclang already configured")
endif()

function(try_find_libclang)
    if(USER_LIBCLANG_SEARCH_PATH)
        message(STATUS "Looking for libclang in user path: ${USER_LIBCLANG_SEARCH_PATH}")
    endif()

    set(possible_paths
        # User search path
        "${USER_LIBCLANG_SEARCH_PATH}"
        # Ubuntu
        "/usr/lib/llvm-4.0/lib"
        "/usr/lib/llvm-3.9/lib"
        "/usr/lib/llvm-3.8/lib"
        "/usr/lib/llvm-3.7/lib"
        # MacOSX
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
        "/Applications/Xcode.app/Contents/Frameworks"
        # fallback
        "/usr/lib64/llvm"
    )

    # will only try to find if the user has NOT set it
    find_library(LIBCLANG_LIB_PATH
        NAMES clang
        PATHS ${possible_paths}
        )
endfunction()

try_find_libclang()

if(LIBCLANG_LIB_PATH STREQUAL "LIBCLANG_LIB_PATH-NOTFOUND")
    message(FATAL_ERROR " libclang.so not found")
else()
    get_filename_component(LIBCLANG_LIB ${LIBCLANG_LIB_PATH} NAME)
    get_filename_component(LIBCLANG_DIR_PATH ${LIBCLANG_LIB_PATH} DIRECTORY)
endif()

if(NOT LIBCLANG_LDFLAGS)
    # -rpath is relative path for all linked libraries.
    # The second "." is argument to rpath.
    if(APPLE)
        set(LIBCLANG_LDFLAGS_OS "-L-rpath -L${LIBCLANG_DIR_PATH} -L-lclang")

    elseif(UNIX)
        set(LIBCLANG_LDFLAGS_OS "-L--enable-new-dtags -L-rpath=. -L--no-as-needed -L-l:${LIBCLANG_LIB}")
    else()
    endif()

    set(LIBCLANG_LDFLAGS "-L-L${LIBCLANG_DIR_PATH} ${LIBCLANG_LDFLAGS_OS}")
endif()

message(STATUS "libclang: ${LIBCLANG_LIB_PATH}")
message(STATUS "libclang name: ${LIBCLANG_LIB}")
message(STATUS "libclang linker flags: ${LIBCLANG_LDFLAGS}")
