# Handy tools
(when in the test/ directory)
../build/devtool dumpast testdata/uml/dev/bug_typedef_func.h
clang++ -Xclang -ast-dump testdata/uml/dev/bug_typedef_func.h

# dump LLVM IR

To dump the IR in a human readable format.
```sh
clang -S -emit-llvm foo.cpp
```

To dump in the binary format.
```sh
clang foo.cpp -o foo.bc
```
