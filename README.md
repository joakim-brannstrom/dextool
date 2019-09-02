# dextool [![Build Status](https://dev.azure.com/wikodes/wikodes/_apis/build/status/joakim-brannstrom.dextool?branchName=master)](https://dev.azure.com/wikodes/wikodes/_build/latest?definitionId=1&branchName=master) [![codecov](https://codecov.io/gh/joakim-brannstrom/dextool/branch/master/graph/badge.svg)](https://codecov.io/gh/joakim-brannstrom/dextool)

**Dextool** is a framework for writing plugins using libclang. The main focus
is tools for testing and static analysis.

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
 * [D compiler](https://dlang.org/download.html) (dmd 2.081.2+, ldc 1.11.0+)
 * [sqlite3](https://sqlite.org/download.html) (3.19.3-3+)

Dextool has been tested with libclang [4.0, 5.0, 6.0, 7.0, 8.0].

For people running Ubuntu two of the dependencies can be installed via apt-get.
The version of clang and llvm depend on your ubuntu version.
```sh
sudo apt install build-essential cmake llvm-4.0 llvm-4.0-dev clang-4.0 libclang-4.0-dev libsqlite3-dev
```

It is recommended to install the D compiler by downloading it from the official distribution page.
```sh
# link https://dlang.org/download.html
curl -fsS https://dlang.org/install.sh | bash -s dmd
```

Once you have a D compiler, you also have access to the D package manager `dub`. The easiest way to run dextool is to do it via `dub`.
```sh
dub run dextool -- -h
```

But if you want to, you can always download the source code and build it yourself:
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

## component_tests Fail

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

### Mismatch Clang and LLVM

To build dextool, the dev packages are required. Dextool is optimistic and assume that the latest and greatest version of llvm+libclang should be used. But this also requires that the dev packages are installed.

If you get this error:
```sh
libclang_interop.hpp:13:10: fatal error: clang/Analysis/CFG.h: No such file or directory
 #include <clang/Analysis/CFG.h>
```

It means that you need to install `llvm-x.y-dev` and `libclang-x.y-dev` for the version that Dextool detected.

### SQLite link or missing

The sqlite3 library source code with a CMake build file in the vendor's directory. It is intended for those old OSs that have too old versions of SQLite.

To use it do something like this.
```sh
mkdir sqlite3
cd sqlite3 && cmake ../vendor/sqlite && make && cd ..
# setup dextool build to use it
mkdir build
cd build && cmake .. -DSQLITE3_LIB="-L/opt/sqlite -lsqlite3"
```

# Usage

See the usage examples in respective plugin directory:
 * [mutate](plugin/mutate/examples)

# Credit
Jacob Carlborg for his excellent DStep. It was used as a huge inspiration for
this code base. Without DStep, Dextool wouldn't exist.
