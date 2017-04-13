# Intro
This directory contains plugins.

# Extend

## CMake Configuration

If the new plugin wants to reuse the main function in source/dextool/plugin/main
add the source:
${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d

with the compiler include:
-I${CMAKE_SOURCE_DIR}/source
-J${CMAKE_SOURCE_DIR}/clang/resources
