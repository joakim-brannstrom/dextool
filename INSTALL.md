# Generic Build Instructions

# Setup
To build deXtool you need a [D compiler] installed. You also need to tell the
build system where libclang is. For most users it is enough to source config.sh.
If that doesn't work export the following variables to point to the directory
and name of the libclang.so to use:

 - LFLAG_CLANG_PATH, example "-Lsome/path/to/where/$LFLAG_CLANG_LIB".
 - LFLAG_CLANG_LIB, example ":libclang.so.1". It is the exact name of the lib.

# Build

## Make
```bash
source ./config.sh

make dmd
# or
make ldc2
```

## Dub
```bash
source ./config.sh

dub build
# or
./build.sh
```

[D compiler]: <https://dlang.org/download.html>