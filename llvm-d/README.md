llvm-d
========

[![Build Status](https://travis-ci.org/Calrama/llvm-d.svg?branch=master)](https://travis-ci.org/Calrama/llvm-d) <a href="https://code.dlang.org/packages/llvm-d" title="Go to llvm-d"><img src="https://img.shields.io/dub/v/llvm-d.svg" alt="Dub version"></a><a href="https://code.dlang.org/packages/llvm-d" title="Go to llvm-d"> <img src="https://img.shields.io/dub/dt/llvm-d.svg" alt="Dub downloads"></a>

llvm-d provides bindings to LLVM's C API for the D programming language.
It is designed to be linked dynamically against LLVM.

Usage
-----

1. `import llvm;` all of LLVM's C API's functions should be available
2. Link against either the correct library (LLVM built as singleton), or the correct libraries (LLVM built as several libraries)
   *Note:* That includes ensuring your linker can find them

For example:

```d
import std.stdio;

import llvm;

void main(string[] args)
{
	static if((asVersion(3, 3, 0) <= LLVM_Version) && (LLVM_Version < asVersion(3, 5, 0)))
	{
		writefln("LLVM multithreading on? %s", cast(bool) LLVMIsMultithreaded());
		writefln("Turning it on"); LLVMStartMultithreaded();
		writefln("LLVM multithreading on? %s", cast(bool) LLVMIsMultithreaded());
		writefln("Turning it off"); LLVMStopMultithreaded();
		writefln("LLVM multithreading on? %s", cast(bool) LLVMIsMultithreaded());
	}
}
```

Note that a `static if` is used to ensure the function calls are only compiled
in if llvm-d is set to compile for a viable LLVM version
(the multithreaded functions where added to LLVM's C API in the 3.3 development
cycle and removed in the 3.5 development cycle; thus they are only available in versions 3.3 and 3.4).

A more complex example showing how to create a jitted function calculating
the fibonacci series can be seen at `examples/fibonacci/fibonacci.d`.

LLVM versions
-------------

The LLVM version to be used is selected by setting a [conditional compilation version identifier](https://dlang.org/spec/version.html).
For DMD, this is the `-version` argument; for dub, the `versions` field.

The identifier to set the LLVM version is defined as
`LLVM_{MAJOR_VERSION}_{MINOR_VERSION}_{PATCH_VERSION}`, so to get LLVM version 3.1.0 use `LLVM_3_1_0`.

Current supported versions are 3.1.0 - 4.0.0 and if no version is given
at compile time, 4.0.0 will be assumed.

LLVM targets
------------

As with the LLVM version, LLVM targets are also selected by setting an appropriate [conditional compilation version identifier](https://dlang.org/spec/version.html).

The identifier to enable an LLVM target XyZ is defined as
`LLVM_Target_XyZ`, which will instruct llvm-d to assume any C API functions for those targets will be linked in, so to enable the X86 LLVM target, use `LLVM_Target_X86`.

*Note*: The target name is case sensitive.

*Note*: Multiple targets can be enabled in this manner.

llvm-d supports all targets for the supported LLVM versions and if no target is given at compile time, none will be assumed to be available.
The dub package's default configuration sets the appropriate identifier to enable the native target for some common platforms.

Documentation
-------------

llvm-d exposes C linkage functions, constants, and types with the same names as LLVM's C API.
[See the LLVM Doxygen pages for a reference.](http://llvm.org/doxygen/modules.html)

License
-------

llvm-d is released under the [MIT license](http://opensource.org/licenses/MIT), see LICENSE.txt.

llvm-d uses source code from LLVM that has been ported to D for accessing LLVM's C API. The above paragraph does not apply
to that source code - it is a redistribution of LLVM source code.

LLVM is Copyright (c) 2003-2017 University of Illinois at Urbana-Champaign.
All rights reserved.

LLVM is distributed under the University of Illinois Open Source
License. See http://opensource.org/licenses/UoI-NCSA.php for details.
