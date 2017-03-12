# Usage
This file describes use cases and other useful information of how to use the
plugins.

# Plugin C TestDouble

## Generate a simple C test double.
```
dextool ctestdouble --in functions.h
```

Analyze and generate a test double for function prototypes and extern variables.
Both those found in functions.h and outside, aka via includes.

The test double is written to ./test_double.hpp/.cpp.
The name of the interface is Test_Double.

## Generate a C test double excluding data from specified files.
```
dextool ctestdouble --file-exclude=/foo.h --file-exclude='functions\.[h,c]' --out=outdata/ --in functions.h -- -DBAR -I/some/path
```

The code analyzer (Clang) will be passed the compiler flags -DBAR and -I/some/path.
During generation declarations found in foo.h or functions.h will be excluded.

The file holding the test double is written to directory outdata.

# Plugin C++ Test Double

TBD

# Plugin UML

TBD

# Plugin GraphML

TBD
