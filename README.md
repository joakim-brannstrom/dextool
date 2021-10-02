# dextool [![Build Status](https://dev.azure.com/wikodes/wikodes/_apis/build/status/joakim-brannstrom.dextool?branchName=master)](https://dev.azure.com/wikodes/wikodes/_build/latest?definitionId=1&branchName=master)

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
   Tested versions are 4.0, 5.0, 6.0, 7.0, 8.0, 10.0, 11.0 and 12.0
 * llvm-xyz-dev >= 4.0
 * libclang-xyz-dev >= 4.0
 * [cmake](https://cmake.org/download) >= 3.5
 * [sqlite3](https://sqlite.org/download.html) >= 3.24.0
 * [D compiler](https://dlang.org/download.html) (dmd >= 2.096.1 or ldc >= 1.26.0)

**NOTE** only ldc is able to build a release build of dextool. dmd is for debug
build. Which mean that for a *normal* user it is ldc that you should use.

Most of them can be installed using your package manager.

Installation instructions for Ubuntu is available [here](doc/install).
Dockerfile are another alternative (they MAY be outdated until the CI is fixed
to check them so if they fail for you ping me on github):

* [Ubuntu](Docker/dextool-ubuntu-focal)
* [Fedora](Docker/dextool-fedora-34)

### Build and Install

The easiest way to build and run dextool is to do it via `dub`:
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
make install
```

Done! Have fun.
Don't be shy to report any issue that you find.

### Common Build Errors

#### ldc is killed

To build dextool comfortably you need ~16Gbyte of RAM. Compiling
`dextool-mutate.o` consume ~9Gbyte.

You probably ran out of memory when compiling `dextool-mutate.o`. Run cmake
with `-DLOW_MEM=ON` and single threaded.

#### `dub` run dextool fail

This method of running dextool assume that the `llvm-config` commands found in
`$PATH` is named and behave as the ones on Ubuntu. Such that `llvm-config-12`
returns the flags for llvm-12 and clang-12. There are also some assumptions of
what the libraries that are installed are named. On Fedora for example the
clang-libraries are `clang-cpp` and `clang`. So if this method of running
dextool fail and you are on ubuntu then you need to install the necessary
dependencies otherwise use the other installation method together with the more
complex flags for specifying the llvm/clang versions.

#### component_tests Fail

The most common reason for why `component_tests` fail is that clang++ try to
use the latest GCC that is installed, but the c++ standard library is not
installed for that compiler.

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

To build dextool, the dev packages are required. Dextool is optimistic and
assume that the latest and greatest version of llvm+libclang should be used.
But this also requires that the dev packages are installed.

If you get this error:
```sh
libclang_interop.hpp:13:10: fatal error: clang/Analysis/CFG.h: No such file or directory
 #include <clang/Analysis/CFG.h>
```

It means that you need to install `llvm-x.y-dev` and `libclang-x.y-dev` for the
version that Dextool detected.

### Bypass llvm-config

`cmake/introspect_llvm_.d` try to derive the version of llvm/clang from
`llvm-config`. If this fail or you want to force a specific version of
llvm/clang you do it with these flags:

The following variables are defined:
* LIBCLANG_LDFLAGS          - flags to use when linking with libclang
* LIBLLVM_VERSION           - libLLVM full version (e.g. 8_0_1)
* LIBLLVM_MAJOR_VERSION     - libLLVM major version (e.g. 8)
* LIBLLVM_LDFLAGS           - flags to use when linking with libllvm
* LIBLLVM_CXX_FLAGS         - the required flags to build C++ code using LLVM
* LIBLLVM_CXX_EXTRA_FLAGS   - extra flags to use when build C++ code using LLVM
* LIBLLVM_FLAGS             - the required flags by llvm-d such as version
* LIBLLVM_LIBS              - the required libraries for linking LLVM

Lets say you have version `8.0.1` of LLVM installed but llvm-config returns
`0.0.0`. `introspect_llvm.d` will in this case fail to detect the version of
LLVM thus what version of the bindings is unknown, which will default to the
latest known by `introspect_llvm.d`. This is probably not the version you have.
To tell cmake what version it is you can do the following:

```sh
# llvm-config --version
cmake -DLIBLLVM_VERSION="LLVM_8_0_1" \
-DLIBLLVM_MAJOR_VERSION="8"
```

If you also need to provide the includes and libs you would need to add the
rest of the flags, otherwise they are derived from whatever `llvm-config` that
is in `$PATH`.

```sh
# uses llvm-config --libdir to find where libclang.so is installed. Some
# additional flags are added but these are optional.
-DLIBLCANG_LDFLAGS="-Wl,--enable-new-dtags -Wl,--no-as-needed -L/foo/bar/libs -Wl,-rpath,/foo/bar/libs -l:libclang.so.8"
# llvm-config --libdir is searched for these libraries.
-DLIBCLANG_LIBS="-lclangFrontendTool -lclangRewriteFrontend -lclangDynamicASTMatchers -lclangFrontend -lclangASTMatchers -lclangParse -lclangSerialization -lclangRewrite -lclangSema -lclangEdit -lclangAnalysis -lclangAST -lclangLex -lclangBasic -l:libclang.so"
# llvm-config --cxxflags
-DLIBLLVM_CXX_FLAGS="-I/foo/bar/llvm-include -std=c++11 -fno-exceptions -fno-rtti"
# llvm-config --ldflags
-DLIBLLVM_LDFLAGS="-L/foo/smurf/libs -Wl,-rpath,/foo/smurf/libs"
# use llvm-config --libs and llvm-config --system-libs to find all libraries to link with.
# all those that are prefixed with libLLVM.
-DLIBLLVM_LIBS="-lLLVMXRay -lLLVMTextApi /*and maaaany more or just one depending on how you have installed LLVM*/"
```

#### SQLite link or missing

The sqlite3 library source code with a CMake build file in the vendor's
directory. It is intended for those old OSs that have too old versions of
SQLite.

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
your `$PATH` you can specify it manually.

```sh
cmake .. -DD_COMPILER=/foo/bar/dmd/2.088/linux64/bin/dmd
```

## Usage

See the usage examples in respective plugin directory.

# Credit

Jacob Carlborg for his excellent DStep. It was used as a huge inspiration for
this code base. Without DStep, Dextool wouldn't exist.
