/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Convenient functions for accessing files via a priority list such that there
are defaults installed in e.g. /etc while a user can override them in their
home directory.
*/
module my.resource;

import logger = std.experimental.logger;
import std.algorithm : filter, map, joiner;
import std.array : array;
import std.file : thisExePath;
import std.path : dirName, buildPath, baseName;
import std.process : environment;
import std.range : only;

import my.named_type;
import my.optional;
import my.path;
import my.xdg : xdgDataHome, xdgConfigHome, xdgDataDirs, xdgConfigDirs;

alias ResourceFile = NamedType!(AbsolutePath, Tag!"ResourceFile",
        AbsolutePath.init, TagStringable);

@safe:

private AbsolutePath[Path] resolveCache;

/// Search order is the users home directory, beside the binary followed by XDG data dir.
AbsolutePath[] dataSearch(string programName) {
    // dfmt off
    AbsolutePath[] rval = only(only(xdgDataHome ~ programName,
                                    Path(buildPath(thisExePath.dirName, "data")),
                                    Path(buildPath(thisExePath.dirName.dirName, "data"))
                                    ).map!(a => AbsolutePath(a)).array,
                               xdgDataDirs.map!(a => AbsolutePath(buildPath(a, programName, "data"))).array
                               ).joiner.array;
    // dfmt on

    return rval;
}

/// Search order is the users home directory, beside the binary followed by XDG config dir.
AbsolutePath[] configSearch(string programName) {
    // dfmt off
    AbsolutePath[] rval = only(only(xdgDataHome ~ programName,
                                    Path(buildPath(thisExePath.dirName, "config")),
                                    Path(buildPath(thisExePath.dirName.dirName, "config"))
                                    ).map!(a => AbsolutePath(a)).array,
                               xdgDataDirs.map!(a => AbsolutePath(buildPath(a, programName, "config"))).array
                               ).joiner.array;
    // dfmt on

    return rval;
}

@("shall return the default locations to search for config resources")
unittest {
    auto a = configSearch("caleb");
    assert(a.length >= 3);
    assert(a[0].baseName == "caleb");
    assert(a[1].baseName == "config");
    assert(a[2].baseName == "config");
}

@("shall return the default locations to search for data resources")
unittest {
    auto a = dataSearch("caleb");
    assert(a.length >= 3);
    assert(a[0].baseName == "caleb");
    assert(a[1].baseName == "data");
    assert(a[2].baseName == "data");
}

/** Look for `lookFor` in `searchIn` by checking if the file exists at
 * `buildPath(searchIn[i],lookFor)`.
 *
 * The result is cached thus further calls will use a thread local cache.
 *
 * Params:
 *  searchIn = directories to search in starting from index 0.
 *  lookFor = the file to search for.
 */
Optional!ResourceFile resolve(const AbsolutePath[] searchIn, const Path lookFor) @trusted {
    import std.file : dirEntries, SpanMode, exists;

    if (auto v = lookFor in resolveCache) {
        return some(ResourceFile(*v));
    }

    foreach (const sIn; searchIn) {
        try {
            AbsolutePath rval = sIn ~ lookFor;
            if (exists(rval)) {
                resolveCache[lookFor] = rval;
                return some(ResourceFile(rval));
            }

            foreach (a; dirEntries(sIn.value, SpanMode.shallow).filter!(a => a.isDir)) {
                rval = AbsolutePath(Path(a.name) ~ lookFor);
                if (exists(rval)) {
                    resolveCache[lookFor] = rval;
                    return some(ResourceFile(rval));
                }
            }

        } catch (Exception e) {
            logger.trace(e.msg);
        }
    }

    return none!ResourceFile();
}

@("shall find the local file")
@system unittest {
    import std.file : exists;
    import std.stdio : File;
    import my.test;

    auto testEnv = makeTestArea("find_local_file");

    File(testEnv.inSandbox("foo"), "w").write("bar");
    auto res = resolve([testEnv.sandboxPath], Path("foo"));
    assert(exists(res.orElse(ResourceFile.init).get));

    auto res2 = resolve([testEnv.sandboxPath], Path("foo"));
    assert(res == res2);
}

/// A convenient function to read a file as a text string from a resource.
string readResource(const ResourceFile r) {
    import std.file : readText;

    return readText(r.get);
}
