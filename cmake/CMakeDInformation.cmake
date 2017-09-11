if( __CMAKE_D_INFORMATION )
    return()
endif()
set(__CMAKE_D_INFORMATION)

#set(CMAKE_D_CREATE_SHARED_LIBRARY "")
#set(CMAKE_D_CREATE_SHARED_MODULE "")
#set(CMAKE_D_CREATE_STATIC_LIBRARY "")

set(CMAKE_D_COMPILE_OBJECT "<CMAKE_D_COMPILER> -od<OBJECT_DIR> <FLAGS> -c <SOURCE>")
set(CMAKE_INCLUDE_FLAG_D "-I")

# Link against static libraries
#SET(CMAKE_LIBRARY_PATH_FLAG "-L+")
#SET(CMAKE_LINK_LIBRARY_FLAG "lib")
#SET(CMAKE_LINK_LIBRARY_PREFIX "lib")
#SET(CMAKE_LINK_LIBRARY_SUFFIX ".a")

# archive program
#set(CMAKE_AR "ar")
        #COMMAND ${D_COMPILER} -of${output_o} ${d_flags} -c ${input_d}

# Flags from ExtractDMDSystemLinker.cmake
list(APPEND _D_LINKERFLAG_LIST ${D_LINKER_ARGS})
if(NOT "${CMAKE_EXE_LINKER_FLAGS}" STREQUAL "")
    separate_arguments(flags UNIX_COMMAND "${CMAKE_EXE_LINKER_FLAGS}")
    list(APPEND _D_LINKERFLAG_LIST ${flags})
endif()
string(REPLACE ";" " " _D_LINKERFLAG_LIST "${_D_LINKERFLAG_LIST}")

# Link object files to an executable
set(CMAKE_D_LINK_EXECUTABLE "${D_LINKER_COMMAND} -o<TARGET> <CMAKE_D_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> <LINK_LIBRARIES> ${_D_LINKERFLAG_LIST}")

# -lib. create static library
set(CMAKE_D_CREATE_STATIC_LIBRARY "<CMAKE_D_COMPILER> -lib -of<TARGET> <OBJECTS>")

## set java include flag option and the separator for multiple include paths
#set(CMAKE_INCLUDE_FLAG_Java "-classpath ")
#if(WIN32 AND NOT CYGWIN)
#  set(CMAKE_INCLUDE_FLAG_SEP_Java ";")
#else()
#  set(CMAKE_INCLUDE_FLAG_SEP_Java ":")
#endif()
