/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

A variaty of libc bindings.
*/
module my.libc;

// malloc_trim - release free memory from the heap
extern (C) int malloc_trim(size_t pad) nothrow @system;
