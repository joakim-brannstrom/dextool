# dextool [![Build Status](https://travis-ci.org/joakim-brannstrom/dextool.svg?branch=master)](https://travis-ci.org/joakim-brannstrom/dextool) [![codecov](https://codecov.io/gh/joakim-brannstrom/dextool/branch/master/graph/badge.svg)](https://codecov.io/gh/joakim-brannstrom/dextool)

**Dextool** is a framework for writing plugins using libclang. The main focus
is tools for testing and analyze.

The plugins in a standard installation of Dextool are:
 - Analyze. Analyze C/C++ code to generate complexity numbers such as McCabe.
 - C TestDouble. Analyze C code to generate a test double implementation.
 - C++ TestDouble. Analyze C++ code to generate a test double implementation.
 - Mutate. Mutation testing tool for C/C++.
 - GraphML. Analyze C/C++ code to generate a GraphML representation.
   Call chains, type usage, classes as _groups_ of methods and members.
 - UML. Analyze C/C++ code to generate PlantUML diagrams.

# Plugin Status

 * **Analyze**: production ready.
 * **C TestDouble**: production ready. The API of the generated code and how it behaves is stable.
 * **C++ TestDouble** is production ready. The API of the generated code and how it behaves is stable.
 * **Fuzzer**: alpha.
 * **GraphML**: beta.
 * **UML**: beta.
 * [**Mutate**](plugin/mutate/README.md): production ready.

# Getting Started

Dextool depends on the following software packages:

 * [llvm](http://releases.llvm.org/download.html) (4.0+, both libclang and LLVM is needed)
 * [cmake](https://cmake.org/download) (3.5+)
 * [D compiler](https://dlang.org/download.html) (dmd 2.076.1+, ldc 1.8.0+)
 * [sqlite3](https://sqlite.org/download.html) (3.19.3-3+)

Dextool has been tested with libclang [4.0, 5.0].

For people running Ubuntu two of the dependencies can be installed via apt-get.
The version of clang and llvm depend on your ubuntu version.
```sh
sudo apt install build-essential cmake llvm-4.0 llvm-4.0-dev clang-4.0 libclang-4.0-dev libsqlite3-dev ldc dub
```

Once the dependencies are installed it is time to download the source code and
build the binaries.
```sh
git clone https://github.com/joakim-brannstrom/dextool.git
cd dextool
mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX=/path/to/where/to/install/dextool/binaries ..
make install -j2
```

Done! Have fun.
Don't be shy to report any issue that you find.

## Common Build Errors

### Mismatch Clang and LLVM

To build dextool the dev packages are required. Dextool is optimistic and assume that the latest and greatest version of llvm+libclang should be used. But this also requires that the dev packages are installed.

If you get this error:
```sh
libclang_interop.hpp:13:10: fatal error: clang/Analysis/CFG.h: No such file or directory
 #include <clang/Analysis/CFG.h>
```

It means that you need to install `llvm-x.y-dev` and `libclang-x.y-dev` for the version that Dextool detected.

# Usage

See the usage examples in respective plugin directory:
 * [mutate](plugin/mutate/examples)

# Credit
Jacob Carlborg for his excellent DStep. It was used as a huge inspiration for
this code base. Without DStep Dextool wouldn't exist.
