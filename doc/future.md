# Clang API usage

## Evaluate expressions

```cpp
CINDEX_LINKAGE CXEvalResult clang_Cursor_Evaluate(CXCursor C);

```

It seems like future versions (2016-08-13+) of the clang API can evaluate expressions.

In an activity diagram it could be used to try and evaluate the branches to, if possible, eliminate branches that aren't possible to take.
For example an hard-coded `if (true)`.

Could also be used to find branches that have complex expressions that the programmer doesn't realize is statically evaluated.

For mutation testing it could maybe be used when combining mutations with MC/DC.

## Find constructors/destructors
Repo version of libclang has convenient API's to find c'tors etc.
They would be useful to simplify the design of test double generators.

```cpp
CINDEX_LINKAGE unsigned clang_CXXConstructor_isConvertingConstructor(CXCursor C);
CINDEX_LINKAGE unsigned clang_CXXConstructor_isCopyConstructor(CXCursor C);
CINDEX_LINKAGE unsigned clang_CXXConstructor_isDefaultConstructor(CXCursor C);
CINDEX_LINKAGE unsigned clang_CXXConstructor_isMoveConstructor(CXCursor C);
CINDEX_LINKAGE unsigned clang_CXXField_isMutable(CXCursor C);
CINDEX_LINKAGE unsigned clang_CXXMethod_isDefaulted(CXCursor C);
```

Also especially annoying that 3.7 lack functionality to query if a "= default" is used.
In the API from the repo it is now possible with clang_CXXMethod_isDefaulted.

# Abbreviations

## MC/DC
Modified coverage/Decision coverage
