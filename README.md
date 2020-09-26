# dextool [![Build Status](https://dev.azure.com/wikodes/wikodes/_apis/build/status/joakim-brannstrom.dextool?branchName=master)](https://dev.azure.com/wikodes/wikodes/_build/latest?definitionId=1&branchName=master) [![codecov](https://codecov.io/gh/joakim-brannstrom/dextool/branch/master/graph/badge.svg)](https://codecov.io/gh/joakim-brannstrom/dextool)

**Dextool** is a framework for writing plugins using libclang. The main focus
is tools for testing and static analysis.

The plugins in a standard installation of Dextool are:
 - Analyze. Analyze C/C++ code to generate complexity numbers such as McCabe.
 - C TestDouble. Analyze C code to generate a test double implementation.
 - C++ TestDouble. Analyze C++ code to generate a test double implementation.
 - Mutate. Mutation testing tool for C/C++.
 - UML. Analyze C/C++ code to generate PlantUML diagrams.

## Plugin Status

 * **Analyze**: production ready.
 * **C TestDouble**: production ready. The API of the generated code and how it behaves is stable.
 * **C++ TestDouble**: production ready. The API of the generated code and how it behaves is stable.
 * [**Mutate**](plugin/mutate/README.md): production ready.
 * **Fuzzer**: alpha.
 * **UML**: beta.

## Installation

### Dependencies

To build and run dextool, you will need the following packages:

 * [llvm](http://releases.llvm.org/download.html) >= 4.0
 * llvm-xyz-dev >= 4.0
 * libclang-xyz-dev >= 4.0
 * [cmake](https://cmake.org/download) >= 3.5
 * [sqlite3](https://sqlite.org/download.html) >= 3.19.3-3
 * [D compiler](https://dlang.org/download.html) (dmd >= 2.092.1 or ldc >= 1.22.0)

Most of them can be installed using your package manager.

Installation instructions for Ubuntu is available in the [doc/install](doc/install) directory.

### Build and Install

The easiest way to build and run dextool is to do it via `dub`.
```sh
dub run dextool -- -h
```

But if you want to, these are the steps to build it using CMake:

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

### Common Build Errors

#### component_tests Fail

The most common reason for why `component_tests` fail is that clang++ try to use the latest GCC that is installed, but the c++ standard library is not installed for that compiler.

Try to compile the following code with clang++:
```c++
#include <string>

int main(int argc, char **argv) {
    return 0;
}
```

```sh
clang++ -v test.cpp
```

If it fails with something like this:
```sh
test.cpp:1:10: fatal error: 'string' file not found
```

it means that you need to install the c++ standard library for your compiler.

In the output look for this line:
```sh
 /usr/bin/../lib/gcc/x86_64-linux-gnu/XYZ/../../../../include/c++
```

From that line we can deduce that the package to install in Ubuntu is:
```sh
sudo apt install libstdc++-XYZ-dev
```

#### Mismatch Clang and LLVM

To build dextool, the dev packages are required. Dextool is optimistic and assume that the latest and greatest version of llvm+libclang should be used. But this also requires that the dev packages are installed.

If you get this error:
```sh
libclang_interop.hpp:13:10: fatal error: clang/Analysis/CFG.h: No such file or directory
 #include <clang/Analysis/CFG.h>
```

It means that you need to install `llvm-x.y-dev` and `libclang-x.y-dev` for the version that Dextool detected.

#### SQLite link or missing

The sqlite3 library source code with a CMake build file in the vendor's directory. It is intended for those old OSs that have too old versions of SQLite.

To use it do something like this.
```sh
mkdir sqlite3
cd sqlite3 && cmake ../vendor/sqlite && make && cd ..
# setup dextool build to use it
mkdir build
cd build && cmake .. -DSQLITE3_LIB="-L/opt/sqlite -lsqlite3"
```

#### Cmake is unable to find the D compiler

If you have a D compiler installed in such a way that it isn't available in
your `$PATH` you can specify it manully.

```sh
cmake .. -DD_COMPILER=/foo/bar/dmd/2.088/linux64/bin/dmd
```

## Usage

See the usage examples in respective plugin directory.

# Credit
Jacob Carlborg for his excellent DStep. It was used as a huge inspiration for
this code base. Without DStep, Dextool wouldn't exist.
