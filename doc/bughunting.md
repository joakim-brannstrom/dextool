# Handy tools
(when in the test/ directory)
../build/devtool dumpast testdata/uml/dev/bug_typedef_func.h
clang++ -Xclang -ast-dump testdata/uml/dev/bug_typedef_func.h
