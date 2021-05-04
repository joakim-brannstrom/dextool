#/bin/bash

set -ex

if [ $# -eq 0 ]; then
  echo 'Please specify the path to the libclang C header files'
  echo 'Example: ./generate_libclang_bindings.sh /usr/lib/llvm-4.0/include/'

  exit 1
fi

cwd=$(pwd)
pushd "$1"/clang-c
dstep ./*.h \
  -I"$1" \
  --public-submodules \
  --package clang.c \
  --space-after-function-name=false \
  -o "$cwd"/source/clang/c \
  --skip CXCursorVisitorBlock \
  --skip CXCursorAndRangeVisitorBlock \
  --skip clang_visitChildrenWithBlock \
  --skip clang_findReferencesInFileWithBlock \
  --skip clang_findIncludesInFileWithBlock \
  --rename-enum-members
popd

rm -rf c
cp -r $1/clang-c c
