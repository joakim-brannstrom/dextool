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

# Link object files to an executable
set(CMAKE_D_LINK_EXECUTABLE "<CMAKE_D_COMPILER> -of<TARGET> <CMAKE_D_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> <LINK_LIBRARIES>")

# -lib. create static library
set(CMAKE_D_CREATE_STATIC_LIBRARY "<CMAKE_D_COMPILER> -lib -of<TARGET> <OBJECTS>")

## set java include flag option and the separator for multiple include paths
#set(CMAKE_INCLUDE_FLAG_Java "-classpath ")
#if(WIN32 AND NOT CYGWIN)
#  set(CMAKE_INCLUDE_FLAG_SEP_Java ";")
#else()
#  set(CMAKE_INCLUDE_FLAG_SEP_Java ":")
#endif()
