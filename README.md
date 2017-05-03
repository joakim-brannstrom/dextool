# dextool [![Build Status](https://travis-ci.org/joakim-brannstrom/dextool.svg?branch=master)](https://travis-ci.org/joakim-brannstrom/dextool) [![codecov](https://codecov.io/gh/joakim-brannstrom/dextool/branch/master/graph/badge.svg)](https://codecov.io/gh/joakim-brannstrom/dextool)

**deXtool** is a framework for writing plugins using libclang. The main focus
is tools for testing and analyze.

The plugins in a standard installation of deXtool are:
 - C TestDouble. Analyze C code to generate a test double implementation.
 - C++ TestDouble. Analyze C++ code to generate a test double implementation.
 - UML. Analyze C/C++ code to generate PlantUML diagrams.
 - GraphML. Analyze C/C++ code to generate a GraphML representation.
   Call chains, type usage, classes as _groups_ of methods and members.

# Plugin Status

The plugin "C Test Double" is with release v1.0.0 guaranteed to be stable
regarding how the generated code behaves and the how the _user_ interacts with
it.

The other plugins are not stable.
Please open an issue if _you_ need a plugin to stabilize.

# Getting Started

deXtool depends on the following software packages:

 * [libclang](http://releases.llvm.org/download.html) (3.7+)
 * [cmake](https://cmake.org/download) (2.8+)
 * [D compiler](https://dlang.org/download.html) (dmd 2.072+, ldc 1.1.0+)

deXtool has been tested with libclang [3.7, 3.8, 3.9].

For people running Ubuntu two of the dependencies can be installed via apt-get.
The libclang version depend on your ubuntu version.
```sh
sudo apt install cmake libclang-3.9-dev
```

Download the D compiler of your choice, extract it and add to your PATH shell
variable.
```sh
# example with an extracted DMD
export PATH=/path/to/dmd/linux/bin64/:$PATH
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

## Solutions for "Libclang Not Found"

If you have libclang installed in a different location from
/usr/lib/llvm-3.X/lib it is possible to tell cmake where the library.

To supply a new search path use:
```sh
cmake -DUSER_LIBCLANG_SEARCH_PATH=/path/to/directy/where/libclang.so/is ..
```

If cmake still can't find the library then it is possible to force cmake to use
the absolute path to _a_ libclang.so.
```sh
cmake -DLIBCLANG_LIB_PATH=/path/to/libclang.so ..
```

# Credit
Jacob Carlborg for his excellent DStep. It was used as a huge inspiration for
this code base. Without DStep deXTool wouldn't exist.

