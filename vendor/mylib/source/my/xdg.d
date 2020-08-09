/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module contains functions to extract XDG variables to either what they are
configured or the fallback according to the standard at [XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
*/
module my.xdg;

import my.path;

/** Returns the directory to use for program runtime data for the current
 * user with a fallback for older OS:es.
 *
 * `$XDG_RUNTIME_DIR` isn't set on all OS such as older versions of CentOS. If
 * such is the case a directory with equivalent properties when it comes to the
 * permissions are created inside `falllback` and returned. This means that
 * this function should in most cases work. When it fails it means something
 * funky is happening such as someone is trying to hijack your data or
 * `fallback` isn't writable. This is the only case when it will throw an
 * exception.
 *
 * From the specification:
 *
 * $XDG_RUNTIME_DIR defines the base directory relative to which user-specific
 * non-essential runtime files and other file objects (such as sockets, named
 * pipes, ...) should be stored. The directory MUST be owned by the user, and
 * he MUST be the only one having read and write access to it. Its Unix access
 * mode MUST be 0700.
 *
 * The lifetime of the directory MUST be bound to the user being logged in. It
 * MUST be created when the user first logs in and if the user fully logs out
 * the directory MUST be removed. If the user logs in more than once he should
 * get pointed to the same directory, and it is mandatory that the directory
 * continues to exist from his first login to his last logout on the system,
 * and not removed in between. Files in the directory MUST not survive reboot
 * or a full logout/login cycle.
 *
 * The directory MUST be on a local file system and not shared with any other
 * system. The directory MUST by fully-featured by the standards of the
 * operating system. More specifically, on Unix-like operating systems AF_UNIX
 * sockets, symbolic links, hard links, proper permissions, file locking,
 * sparse files, memory mapping, file change notifications, a reliable hard
 * link count must be supported, and no restrictions on the file name character
 * set should be imposed. Files in this directory MAY be subjected to periodic
 * clean-up. To ensure that your files are not removed, they should have their
 * access time timestamp modified at least once every 6 hours of monotonic time
 * or the 'sticky' bit should be set on the file.
 *
 * If $XDG_RUNTIME_DIR is not set applications should fall back to a
 * replacement directory with similar capabilities and print a warning message.
 * Applications should use this directory for communication and synchronization
 * purposes and should not place larger files in it, since it might reside in
 * runtime memory and cannot necessarily be swapped out to disk.
 */
Path xdgRuntimeDir(Path fallback = Path("/tmp")) @safe {
    import std.array : empty;
    import std.process : environment;

    Path backup() @trusted {
        import core.stdc.stdio : perror;
        import core.sys.posix.sys.stat : mkdir;
        import core.sys.posix.sys.stat;
        import core.sys.posix.unistd : getuid;
        import std.file : exists;
        import std.format : format;
        import std.string : toStringz;

        const base = fallback ~ format!"user_%s"(getuid);
        string rval;

        foreach (i; 0 .. 1000) {
            // create
            rval = format!"%s_%s"(base, i);
            const cstr = rval.toStringz;

            if (!exists(rval)) {
                if (mkdir(cstr, S_IRWXU) != 0) {
                    continue;
                }
            }

            // validate
            stat_t st;
            stat(cstr, &st);
            if (st.st_uid == getuid && (st.st_mode & S_IFDIR) != 0
                    && ((st.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO)) == S_IRWXU)) {
                break;
            }

            // try again
            rval = null;
        }

        if (rval.empty) {
            perror(null);
            throw new Exception("Unable to create XDG_RUNTIME_DIR " ~ rval);
        }
        return Path(rval);
    }

    auto xdg = environment.get("XDG_RUNTIME_DIR").Path;
    if (xdg.empty)
        xdg = backup;
    return xdg;
}

@("shall return the XDG runtime directory")
unittest {
    import std.process : environment;

    auto xdg = xdgRuntimeDir;
    assert(xdg == environment.get("XDG_RUNTIME_DIR"));
}
