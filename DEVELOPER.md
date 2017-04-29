# vim: filetype=markdown

This file contains information useful to a developer of deXtool.

# Setup
Compared to a normal installation of deXtool a developer have additional needs
such as compiling a full debug build (contracts activated) and compiling the
tests.

Example:
```sh
mkdir build
cd build
cmake -Wdev -DCMAKE_BUILD_TYPE=Debug -DBUILD_TEST=ON ..
```

This gives access to the make target _test_.

To run the tests:
```sh
make check # runs unittests
make check_integration
```
