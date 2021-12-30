# How to update

Create bindings for a version:
```sh
./generate_libclang_bindings.sh /usr/lib/llvm-XX/include

# Move the files to the correct version:
mkdir XX
mv c source XX
```

Update the llvm introspect script which tells dextool what versions are
available during the cmake generation step.

Open `{git root}/cmake/introspect_llvm.d`

Remove all build directories to re-generate with cmake.
