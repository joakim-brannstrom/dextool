# dextool [![Build Status](https://travis-ci.org/joakim-brannstrom/dextool.svg?branch=master)](https://travis-ci.org/joakim-brannstrom/dextool)

**dextool** is a suite of tools for analyzing and code generation of C/C++ source
code.

# Status
**dextool** is beta quality. Stable release will be 1.0.

# Overview
The current focus is generation of test doubles for C code.

# Building and installing
To build dextool, run ```build.sh```.
You may have to set the environment variable LFLAGS.

# Usage
## Generate a simple C test double.
```
dextool ctestdouble functions.h
```

Analyze and generate a test double for function prototypes and extern variables.
Both those found in functions.h and outside, aka via includes.

The test double is written to ./test_double.hpp/.cpp.
The name of the interface is Test_Double.

## Generate a C test double excluding data from specified files.
```
dextool ctestdouble --file-exclude=/foo.h --file-exclude=functions.[h,c] --out=outdata/ functions.h -- -DBAR -I/some/path
```

The code analyzer (Clang) will be passed the compiler flags -DBAR and -I/some/path.
During generation declarations found in foo.h or functions.h will be excluded.

The file holding the test double is written to directory outdata.

# Credit
Jacob Carlborg for his excellent DStep. It was used as a huge inspiration for
this code base. Without DStep deXTool wouldn't exist.
