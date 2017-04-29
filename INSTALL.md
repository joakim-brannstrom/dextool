# Intro

This file contains installation instructions.

To build deXtool you need a [D compiler] installed and libclang.

[D compiler]: <https://dlang.org/download.html>

# Install Dependencies on Ubuntu

To install the libclang dependency on ubuntu (the libclang version depend on
your ubuntu version):
```sh
sudo apt install cmake libclang-3.9-dev
```

# Build

The simple way:
```sh
make all
make install
```

To change any of the defaults of cmake or the deXtool installation scripts user the following way to configure cmake:
Reminder, see below if you get a warning that libclang isn't found.

```bash
mkdir build
cd build
cmake -D<your config options> ..
make
```

To install in a different directory than the default by cmake:
```sh
cmake -DCMAKE_INSTALL_PREFIX=/your/path
```

# Solutions for "Libclang Not Found"

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
