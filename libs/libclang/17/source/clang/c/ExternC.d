/*===- clang-c/ExternC.h - Wrapper for 'extern "C"' ---------------*- C -*-===*\
|*                                                                            *|
|* Part of the LLVM Project, under the Apache License v2.0 with LLVM          *|
|* Exceptions.                                                                *|
|* See https://llvm.org/LICENSE.txt for license information.                  *|
|* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception                    *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This file defines an 'extern "C"' wrapper.                                 *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

module clang.c.ExternC;

extern (C):

enum LLVM_CLANG_C_STRICT_PROTOTYPES_END = _Pragma("clang diagnostic pop");

enum LLVM_CLANG_C_EXTERN_C_BEGIN = LLVM_CLANG_C_STRICT_PROTOTYPES_BEGIN;
enum LLVM_CLANG_C_EXTERN_C_END = LLVM_CLANG_C_STRICT_PROTOTYPES_END;

