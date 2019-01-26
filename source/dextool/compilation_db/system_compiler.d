/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module can deduce the system compiler flags, if possible, from the
compiler specified in a CompileCommand.

The module assumes that during an execution the system flags for a compiler do
not change thus they can be cached. This avoids having to invoke the compiler
more than necessary.

This module exists for those times that:
 * a cross-compiler which uses other system headers than the hosts system
   compiler. E.g. clang-tidy do not know *what* these are thus this module
   discoveres them and provide them.
 * multiple compiler versions are used in a build and each have different
   headers.
*/
module dextool.compilation_db.system_compiler;

import logger = std.experimental.logger;

import dextool.compilation_db : CompileCommand;

version (unittest) {
    import unit_threaded : shouldBeIn, shouldEqual;
}

@safe:

struct Compiler {
    string value;
    alias value this;
}

struct SystemIncludePath {
    string value;
    alias value this;
}

/** Execute and inspect the compiler for the system includes.
 *
 * Note that how the compilers are inspected is hard coded.
 */
SystemIncludePath[] deduceSystemIncludes(ref CompileCommand cmd, const Compiler compiler) {
    import std.process : execute;

    if (cmd.command.length == 0 || compiler.length == 0)
        return null;

    if (auto v = compiler in cacheSysIncludes) {
        return *v;
    }

    auto args = systemCompilerArg(cmd, compiler);

    auto res = execute(args);
    if (res.status != 0) {
        logger.tracef("Failed to inspect the compiler for system includes: %-(%s %)", args);
        logger.trace(res.output);
        return null;
    }

    auto incls = parseCompilerOutput(res.output);
    cacheSysIncludes[compiler] = incls;

    return incls;
}

private:

string[] systemCompilerArg(ref CompileCommand cmd, const Compiler compiler) {
    string[] args = ["-v", "/dev/null", "-fsyntax-only"];
    if (auto v = language(compiler, cmd.command)) {
        args = [v] ~ args;
    }
    if (auto v = sysroot(cmd.command)) {
        args ~= v;
    }
    return [compiler.value] ~ args;
}

SystemIncludePath[] parseCompilerOutput(T)(T output) {
    import std.algorithm : countUntil, map;
    import std.array : array;
    import std.string : stripLeft, splitLines;

    auto lines = output.splitLines;
    const start = lines.countUntil("#include <...> search starts here:") + 1;
    const end = lines.countUntil("End of search list.");
    if (start == 0 || end == 0)
        return null;

    auto incls = lines[start .. end].map!(a => SystemIncludePath(a.stripLeft)).array;

    return incls;
}

SystemIncludePath[][Compiler] cacheSysIncludes;

// assumes that compilers adher to the gcc and llvm commands use of --sysroot / -isysroot.
// depends on the fact that CompileCommand.Command always splits e.g. a --isysroot=foo to ["--sysroot", "foo"].
string[] sysroot(ref CompileCommand.Command cmd) {
    import std.algorithm : countUntil;
    import std.string : startsWith;

    auto index = cmd.countUntil!(a => a.startsWith("--sysroot")) + 1;
    if (index > 0 && (index + 1) < cmd.length)
        return cmd[index .. index + 1];

    index = cmd.countUntil!(a => a.startsWith("-isysroot")) + 1;
    if (index > 0 && (index + 1) < cmd.length)
        return cmd[index .. index + 1];

    return null;
}

// assumes that compilers adher to the gcc and llvm commands of using -xLANG
string language(Compiler compiler, ref CompileCommand.Command cmd) {
    import std.algorithm : countUntil;
    import std.path : baseName;
    import std.string : startsWith;
    import std.typecons : No;

    auto index = cmd.countUntil!(a => a.startsWith("-x")) + 1;
    if (index > 0)
        return cmd[index];

    switch (compiler.baseName) {
    case "cc":
    case "clang":
    case "gcc":
        return "-xc";
    case "c++":
    case "clang++":
    case "g++":
        return "-xc++";
    default:
    }

    return null;
}

@("shall parse the system flags")
unittest {
    import std.typecons : Tuple;

    // arrange
    immutable compiler_output = `Using built-in specs.
COLLECT_GCC=gcc
COLLECT_LTO_WRAPPER=/usr/lib/gcc/x86_64-linux-gnu/7/lto-wrapper
OFFLOAD_TARGET_NAMES=nvptx-none
OFFLOAD_TARGET_DEFAULT=1
Target: x86_64-linux-gnu
Configured with: ../src/configure -v --with-pkgversion='Ubuntu 7.3.0-27ubuntu1~18.04' --with-bugurl=file:///usr/share/doc/gcc-7/README.Bugs --enable-languages=c,ada,c++,go,brig,d,fortran,objc,obj-c++ --prefix=/usr --with
-gcc-major-version-only --program-suffix=-7 --program-prefix=x86_64-linux-gnu- --enable-shared --enable-linker-build-id --libexecdir=/usr/lib --without-included-gettext --enable-threads=posix --libdir=/usr/lib --enable-n
ls --with-sysroot=/ --enable-clocale=gnu --enable-libstdcxx-debug --enable-libstdcxx-time=yes --with-default-libstdcxx-abi=new --enable-gnu-unique-object --disable-vtable-verify --enable-libmpx --enable-plugin --enable-d
efault-pie --with-system-zlib --with-target-system-zlib --enable-objc-gc=auto --enable-multiarch --disable-werror --with-arch-32=i686 --with-abi=m64 --with-multilib-list=m32,m64,mx32 --enable-multilib --with-tune=generic
 --enable-offload-targets=nvptx-none --without-cuda-driver --enable-checking=release --build=x86_64-linux-gnu --host=x86_64-linux-gnu --target=x86_64-linux-gnu
Thread model: posix
gcc version 7.3.0 (Ubuntu 7.3.0-27ubuntu1~18.04)
COLLECT_GCC_OPTIONS='-v' '-fsyntax-only' '-mtune=generic' '-march=x86-64'
 /usr/lib/gcc/x86_64-linux-gnu/7/cc1 -quiet -v -imultiarch x86_64-linux-gnu /dev/null -quiet -dumpbase null -mtune=generic -march=x86-64 -auxbase null -version -fsyntax-only -o /dev/null -fstack-protector-strong -Wformat
 -Wformat-security
GNU C11 (Ubuntu 7.3.0-27ubuntu1~18.04) version 7.3.0 (x86_64-linux-gnu)
        compiled by GNU C version 7.3.0, GMP version 6.1.2, MPFR version 4.0.1, MPC version 1.1.0, isl version isl-0.19-GMP

GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
ignoring nonexistent directory "/usr/local/include/x86_64-linux-gnu"
ignoring nonexistent directory "/usr/lib/gcc/x86_64-linux-gnu/7/../../../../x86_64-linux-gnu/include"
#include "..." search starts here:
#include <...> search starts here:
 /usr/lib/gcc/x86_64-linux-gnu/7/include/foo
 /usr/local/include
 /usr/lib/gcc/x86_64-linux-gnu/7/include-fixed
 /usr/include/x86_64-linux-gnu
 /usr/include
End of search list.
GNU C11 (Ubuntu 7.3.0-27ubuntu1~18.04) version 7.3.0 (x86_64-linux-gnu)
        compiled by GNU C version 7.3.0, GMP version 6.1.2, MPFR version 4.0.1, MPC version 1.1.0, isl version isl-0.19-GMP

GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
Compiler executable checksum: c8081a99abb72bbfd9129549110a350c
COMPILER_PATH=/usr/lib/gcc/x86_64-linux-gnu/7/:/usr/lib/gcc/x86_64-linux-gnu/7/:/usr/lib/gcc/x86_64-linux-gnu/:/usr/lib/gcc/x86_64-linux-gnu/7/:/usr/lib/gcc/x86_64-linux-gnu/
LIBRARY_PATH=/usr/lib/gcc/x86_64-linux-gnu/7/:/usr/lib/gcc/x86_64-linux-gnu/7/../../../x86_64-linux-gnu/:/usr/lib/gcc/x86_64-linux-gnu/7/../../../../lib/:/lib/x86_64-linux-gnu/:/lib/../lib/:/usr/lib/x86_64-linux-gnu/:/us
r/lib/../lib/:/usr/lib/gcc/x86_64-linux-gnu/7/../../../:/lib/:/usr/lib/
COLLECT_GCC_OPTIONS='-v' '-fsyntax-only' '-mtune=generic' '-march=x86-64'`;

    // act
    auto sysflags = parseCompilerOutput(compiler_output);

    // assert
    "/usr/lib/gcc/x86_64-linux-gnu/7/include/foo".shouldBeIn(sysflags);
    "/usr/local/include".shouldBeIn(sysflags);
    "/usr/lib/gcc/x86_64-linux-gnu/7/include-fixed".shouldBeIn(sysflags);
    "/usr/include/x86_64-linux-gnu".shouldBeIn(sysflags);
    "/usr/include".shouldBeIn(sysflags);
}
