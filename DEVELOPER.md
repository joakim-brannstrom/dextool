# vim: filetype=markdown

This file contains information useful to a developer of Dextool.

# Setup

Compared to a normal installation of Dextool a developer have additional needs
such as compiling a full debug build (contracts activated) and compiling the
tests.

A quick and easy way to setup a development build is to run the script from
`tools`.

Example:
```sh
./tools/dev_setup.d
```

This gives access to the make target _test_.

To run the tests:
```sh
# build and run the unit tests
make check

# build and run the integration tests
make check_integration
```

# API Documentation

This describes how to build the API documentation for Dextool (all plugins and the support libraries).

Re-configure cmake with the documentation directive on:
```sh
cd build
cmake -DBUILD_DOC=ON ..
```

For the documentation tool to run it requires that dmd has created the `.json` files with type information. This is done by rebuilding all modules:
```sh
make clean
make all
```

Now lets generate the documentation with the tool.
```sh
./tools/build_doc.d --ddox
```

If you do not have access to internet, remove the `--ddox` parameter.
