/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Useful utility functions when working with posix/linux OS.
*/
module my.unix;

struct UtsName {
    // Name of this implementation of the operating system.
    string sysname;

    // Name of this node within an implementation-defined communications network.
    string nodename;

    // Current release level of this implementation.
    string release;

    // Current version level of this release.
    string version_;

    // Name of the hardware type on which the system is running.
    string machine;
}

UtsName makeUtsName() @trusted {
    import core.sys.posix.sys.utsname;
    import std.string : fromStringz;

    utsname r;
    if (uname(&r) != 0) {
        throw new Exception("Unable to retrieve utsname");
    }

    return UtsName(r.sysname.ptr.fromStringz.idup,
            r.nodename.ptr.fromStringz.idup, r.release.ptr.fromStringz.idup,
            r.version_.ptr.fromStringz.idup, r.machine.ptr.fromStringz.idup);
}

@("shall retrieve the host information")
unittest {
    auto a = makeUtsName;
    assert(a.nodename != "");
}
