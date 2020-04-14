/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module process.pid;

import core.time : Duration;
import logger = std.experimental.logger;
import std.algorithm : splitter, map, filter, joiner, sort;
import std.array : array, appender, empty;
import std.conv;
import std.exception : collectException, ifThrown;
import std.file;
import std.path;
import std.range : iota;
import std.stdio : File, writeln, writefln;
import std.typecons : Nullable, NullableRef, Tuple, tuple;

import core.sys.posix.sys.types : uid_t;

@safe:

struct RawPid {
    import core.sys.posix.unistd : pid_t;

    pid_t value;
    alias value this;
}

struct PidMap {
    static struct Stat {
        uid_t uid;
    }

    static struct Pid {
        RawPid self;
        Stat stat;
        RawPid[] children;
        RawPid parent;
        string proc;
    }

    Stat[RawPid] stat;
    /// The children a process has
    RawPid[][RawPid] children;
    /// the parent of a process
    RawPid[RawPid] parent;
    /// The executable of a pid
    string[RawPid] proc;

    size_t length() nothrow {
        return stat.length;
    }

    auto pids() nothrow {
        return stat.byKey.array;
    }

    Pid get(RawPid p) nothrow {
        typeof(return) rval;
        rval.self = p;

        if (auto v = p in stat) {
            rval.stat = *v;
        }
        if (auto v = p in children) {
            rval.children = *v;
        }
        if (auto v = p in proc) {
            rval.proc = *v;
        }

        if (auto v = p in parent) {
            rval.parent = *v;
        } else {
            rval.parent = p;
        }

        return rval;
    }

    void put(Pid p) nothrow {
        stat[p.self] = p.stat;
        this.parent[p.self] = p.parent;
        if (p.parent !in stat) {
            stat[p.parent] = Stat.init;
            parent[p.parent] = p.parent;
        }
        if (!p.children.empty) {
            this.children[p.self] = p.children;
        }
        if (!p.proc.empty) {
            this.proc[p.self] = p.proc;
        }
    }

    void putChild(RawPid parent, RawPid child) {
        if (auto v = parent in children) {
            (*v) ~= child;
        } else {
            children[parent] = [child];
        }
    }

    bool empty() nothrow {
        return stat.empty;
    }

    /** Remove a pid from the map.
     *
     * An existing pid that have `p` as its parent will be rewritten such that
     * it is it's own parent.
     *
     * The pid that had `p` as a child will be rewritten such that `p` is
     * removed as a child.
     */
    ref PidMap remove(RawPid p) return nothrow {
        stat.remove(p);
        proc.remove(p);

        if (auto children_ = p in children) {
            foreach (c; *children_) {
                parent[c] = c;
            }
        }
        children.remove(p);

        if (auto children_ = parent[p] in children) {
            (*children_) = (*children_).filter!(a => a != p).array;
        }
        parent.remove(p);

        return this;
    }

    RawPid[] getChildren(RawPid p) nothrow {
        if (auto v = p in children) {
            return *v;
        }
        return null;
    }

    string getProc(RawPid p) nothrow {
        if (auto v = p in proc) {
            return *v;
        }
        return null;
    }

    /// Returns: a `PidMap` that is a subtree with `p` as its root.
    PidMap getSubMap(const RawPid p) nothrow {
        PidMap rval;
        RawPid[] s;
        {
            auto g = get(p);
            g.parent = p;
            rval.put(g);
            s = g.children;
        }
        while (!s.empty) {
            auto f = s[0];
            s = s[1 .. $];

            auto g = get(f);
            rval.put(g);
            s ~= g.children;
        }

        return rval;
    }

    import std.range : isOutputRange;

    string toString() @safe {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;
        import std.range : put;

        formattedWrite(w, "PidMap(\n");
        foreach (n; pids) {
            formattedWrite(w, `Pid(%s, "%s", %s, %s)`, n, getProc(n), getChildren(n), parent[n]);
            put(w, "\n");
        }
        put(w, ")");
    }
}

/** Kill all pids in the map.
 *
 * Repeats until all pids are killed. It will continiue until all processes
 * are killed by generating an updated `PidMap` and inspecting it to see that
 * no new processes have been started.
 *
 * Returns: a pid list of the killed pids that may need to be called wait on.
 *
 * TODO: remove @trusted when upgrading the minimum compiler >2.091.0
 */
RawPid[] kill(PidMap pmap) @trusted nothrow {
    static import core.sys.posix.signal;

    static void killMap(RawPid[] pids) @trusted nothrow {
        foreach (const c; pids) {
            core.sys.posix.signal.kill(c, core.sys.posix.signal.SIGKILL);
        }
    }

    auto rval = appender!(RawPid[])();
    auto toKill = [pmap.filterByCurrentUser];
    while (!toKill.empty) {
        auto f = toKill[0];
        toKill = toKill[1 .. $];

        auto pids = f.pids;
        killMap(pids);
        rval.put(pids);

        pmap = makePidMap.filterByCurrentUser;
        foreach (s; pids.map!(a => tuple(a, pmap.getSubMap(a)))
                .map!(a => a[1].remove(a[0]))
                .filter!(a => !a.empty)) {
            toKill ~= s;
        }
    }

    return rval.data;
}

/// Reap all pids by calling wait on them.
void reap(RawPid[] pids) @trusted nothrow {
    import core.sys.posix.sys.wait : waitpid, WNOHANG;

    foreach (c; pids) {
        waitpid(c, null, WNOHANG);
    }
}

/// Split a `PidMap` so each map have one top pid as the `root`.
Tuple!(PidMap, "map", RawPid, "root")[] splitToSubMaps(PidMap pmap) {
    import std.range : ElementType;

    RawPid[][RawPid] trees;
    RawPid[RawPid] parent;

    void migrate(RawPid from, RawPid to) {
        auto p = parent[to];
        if (auto v = from in trees) {
            trees[p] ~= *v;
            trees.remove(from);
        }

        foreach (k; parent.byKeyValue
                .filter!(a => a.value == from)
                .map!(a => a.key)
                .array) {
            parent[k] = p;
        }
    }

    // populate, simplifies the migration if all nodes exists with an
    // individual tree.
    foreach (n; pmap.pids) {
        parent[n] = n;
        trees[n] = [n];
    }

    foreach (n; pmap.pids) {
        foreach (c; pmap.getChildren(n)) {
            migrate(c, n);
        }
    }

    alias RT = ElementType!(typeof(return));
    auto app = appender!(RT[])();

    foreach (tree; trees.byKeyValue) {
        RT m;
        m.root = tree.key;
        foreach (n; tree.value) {
            m.map.put(pmap.get(n));
        }
        app.put(m);
    }

    return app.data;
}

PidMap makePidMap() @trusted nothrow {
    import std.algorithm : startsWith;
    import std.conv : to;
    import std.path : buildPath, baseName;
    import std.stdio : File;
    import std.string : strip;

    static RawPid parsePpid(string fname) nothrow {
        try {
            static immutable prefix = "PPid:";
            foreach (l; File(fname).byLine.filter!(a => a.startsWith(prefix))) {
                return l[prefix.length .. $].strip.to!int.RawPid;
            }
        } catch (Exception e) {
        }
        return 0.to!int.RawPid;
    }

    static string[] procDirs() nothrow {
        auto app = appender!(string[])();
        try {
            foreach (p; dirEntries("/proc", SpanMode.shallow)) {
                try {
                    if (p.isDir) {
                        app.put(p.name);
                    }
                } catch (Exception e) {
                }
            }
        } catch (Exception e) {
        }
        return app.data;
    }

    PidMap rval;
    foreach (const p; procDirs) {
        try {
            const pid = RawPid(p.baseName.to!int);
            const uid = readText(buildPath(p, "loginuid")).to!uid_t.ifThrown(cast(uid_t) 0);
            const parent = parsePpid(buildPath(p, "status"));

            rval.put(PidMap.Pid(pid, PidMap.Stat(uid), null, parent, null));
            rval.putChild(parent, pid);
        } catch (ConvException e) {
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    return rval;
}

/// Returns: a `PidMap` that only contains those processes that are owned by `uid`.
PidMap filterBy(PidMap pmap, const uid_t uid) nothrow {
    if (pmap.empty)
        return pmap;

    auto rval = pmap;
    foreach (k; pmap.stat
            .byKeyValue
            .filter!(a => a.value.uid != uid)
            .map!(a => a.key)
            .array) {
        rval.remove(k);
    }

    return rval;
}

PidMap filterByCurrentUser(PidMap pmap) nothrow {
    import core.sys.posix.unistd : getuid;

    return filterBy(pmap, getuid());
}

/// Update the executable of all pids in the map
void updateProc(ref PidMap pmap) @trusted nothrow {
    static string parseCmdline(string pid) @trusted {
        import std.utf : byUTF;

        try {
            return readLink(buildPath("/proc", pid, "exe"));
        } catch (Exception e) {
        }

        auto s = appender!(const(char)[])();
        foreach (c; File(buildPath("/proc", pid, "cmdline")).byChunk(4096).joiner) {
            if (c == '\0')
                break;
            s.put(c);
        }
        return cast(immutable) s.data.byUTF!char.array;
    }

    foreach (candidatePid; pmap.pids) {
        try {
            auto cmd = parseCmdline(candidatePid.to!string);
            pmap.proc[candidatePid] = cmd;
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }
}

version (unittest) {
    import unit_threaded.assertions;

    auto makeTestPidMap(int nodes) {
        PidMap rval;
        foreach (n; iota(1, nodes + 1)) {
            rval.put(PidMap.Pid(RawPid(n), PidMap.Stat(n), null, RawPid(n), null));
        }
        return rval;
    }
}

@("shall produce a tree")
unittest {
    auto t = makeTestPidMap(10).pids;
    t.length.shouldEqual(10);
    RawPid(1).shouldBeIn(t);
    RawPid(10).shouldBeIn(t);
}

@("shall produce as many subtrees as there are nodes when no node have a child")
unittest {
    auto t = makeTestPidMap(10);
    auto s = splitToSubMaps(t);
    s.length.shouldEqual(10);
}

@("shall produce one subtree because a node have all the others as children")
unittest {
    auto t = makeTestPidMap(3);
    t.put(PidMap.Pid(RawPid(20), PidMap.Stat(20), [
                RawPid(1), RawPid(2), RawPid(3)
            ], RawPid(20), "top"));
    auto s = splitToSubMaps(t);
    s.length.shouldEqual(1);
}
