/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module contains libc bindings.
*/
module proc.libc;

extern (C) static int forkpty(int* master, char* name, void* termp, void* winp);
extern (C) static char* ttyname(int fd);

extern (C) int openpty(scope int* amaster, scope int* aslave, scope char* name,
        const void* termp, const void* winp);
