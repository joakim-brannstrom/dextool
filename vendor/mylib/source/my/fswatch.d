/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This is based on webfreak's
[fswatch](git@github.com:WebFreak001/FSWatch.git). I had problems with the
API as it where because I needed to be able to watch multiple directories,
filter what files are to be watched and to be robust against broken symlinks.

Lets say you want to watch a directory for changes and add all directories to
be watched too.

---
auto fw = fileWatch();
fw.watchRecurse("my_dir");
while (true) {
    auto ev = fw.wait;
    foreach (e; ev) {
        e.match!(
        (Event.Access x) => writeln(x),
        (Event.Attribute x) => writeln(x),
        (Event.CloseWrite x) => writeln(x),
        (Event.CloseNoWrite x) => writeln(x),
        (Event.Create x) { fw.watchRecurse(x.path); },
        (Event.Delete x) => writeln(x),
        (Event.DeleteSelf x) => writeln(x),
        (Event.Modify x) => writeln(x),
        (Event.MoveSelf x) => writeln(x),
        (Event.Rename x) => writeln(x),
        (Event.Open x) => writeln(x),
        );
    }
}
---
*/
module my.fswatch;

import core.sys.linux.errno : errno;
import core.sys.linux.fcntl : fcntl, F_SETFD, FD_CLOEXEC;
import core.sys.linux.sys.inotify : inotify_rm_watch, inotify_init1,
    inotify_add_watch, inotify_event, IN_NONBLOCK, IN_ACCESS,
    IN_MODIFY, IN_ATTRIB, IN_CLOSE_WRITE, IN_CLOSE_NOWRITE, IN_OPEN, IN_MOVED_FROM, IN_MOVED_TO, IN_CREATE,
    IN_DELETE, IN_DELETE_SELF, IN_MOVE_SELF, IN_UNMOUNT, IN_IGNORED, IN_EXCL_UNLINK;
import core.sys.linux.unistd : close, read;
import core.sys.posix.poll : pollfd, poll, POLLIN, POLLNVAL;
import core.thread : Thread;
import core.time : dur, Duration;
import logger = std.experimental.logger;
import std.array : appender, empty;
import std.conv : to;
import std.file : DirEntry, isDir, dirEntries, rmdirRecurse, write, append,
    rename, remove, exists, SpanMode, mkdir, rmdir;
import std.path : buildPath;
import std.range : isInputRange;
import std.string : toStringz, fromStringz;
import std.exception : collectException;

import sumtype;

import my.path : AbsolutePath, Path;

struct Event {
    /// File was accessed (e.g., read(2), execve(2)).
    static struct Access {
        AbsolutePath path;
        this(this) {
        }
    }

    /** Metadata changed—for example, permissions (e.g., chmod(2)), timestamps
     * (e.g., utimensat(2)), extended attributes (setxattr(2)), link count
     * (since Linux 2.6.25; e.g., for the target of link(2) and for unlink(2)),
     * and user/group ID (e.g., chown(2)).
     */
    static struct Attribute {
        AbsolutePath path;
        this(this) {
        }
    }

    /// File opened for writing was closed.
    static struct CloseWrite {
        AbsolutePath path;
        this(this) {
        }
    }

    /// File or directory not opened for writing was closed.
    static struct CloseNoWrite {
        AbsolutePath path;
        this(this) {
        }
    }

    /** File/directory created in watched directory (e.g., open(2) O_CREAT,
     * mkdir(2), link(2), symlink(2), bind(2) on a UNIX domain socket).
     */
    static struct Create {
        AbsolutePath path;
        this(this) {
        }
    }

    /// File/directory deleted from watched directory.
    static struct Delete {
        AbsolutePath path;
        this(this) {
        }
    }

    /** Watched file/directory was itself deleted. (This event also occurs if
     * an object is moved to another filesystem, since mv(1) in effect copies
     * the file to the other filesystem and then deletes it from the original
     * filesys‐ tem.)  In addition, an IN_IGNORED event will subsequently be
     * generated for the watch descriptor.
     */
    static struct DeleteSelf {
        AbsolutePath path;
        this(this) {
        }
    }

    /// File was modified (e.g., write(2), truncate(2)).
    static struct Modify {
        AbsolutePath path;
        this(this) {
        }
    }

    /// Watched file/directory was itself moved.
    static struct MoveSelf {
        AbsolutePath path;
        this(this) {
        }
    }

    /// Occurs when a file or folder inside a folder is renamed.
    static struct Rename {
        AbsolutePath from;
        AbsolutePath to;
        this(this) {
        }
    }

    /// File or directory was opened.
    static struct Open {
        AbsolutePath path;
        this(this) {
        }
    }
}

alias FileChangeEvent = SumType!(Event.Access, Event.Attribute, Event.CloseWrite,
        Event.CloseNoWrite, Event.Create, Event.Delete, Event.DeleteSelf,
        Event.Modify, Event.MoveSelf, Event.Rename, Event.Open);

/// Construct a FileWatch.
auto fileWatch() {
    int fd = inotify_init1(IN_NONBLOCK);
    if (fd == -1) {
        throw new Exception(
                "inotify_init1 returned invalid file descriptor. Error code " ~ errno.to!string);
    }
    return FileWatch(fd);
}

/// Listens for create/modify/removal of files and directories.
enum ContentEvents = IN_CREATE | IN_DELETE | IN_DELETE_SELF | IN_MODIFY
    | IN_MOVE_SELF | IN_MOVED_FROM | IN_MOVED_TO | IN_EXCL_UNLINK | IN_CLOSE_WRITE;

/// Listen for events that change the metadata.
enum MetadataEvents = IN_ACCESS | IN_ATTRIB | IN_OPEN | IN_CLOSE_NOWRITE | IN_EXCL_UNLINK;

/** An instance of a FileWatcher
 */
struct FileWatch {
    import std.functional : toDelegate;

    private {
        int fd;
        ubyte[1024 * 4] eventBuffer; // 4kb buffer for events
        struct FDInfo {
            int wd;
            bool watched;
            Path path;

            this(this) {
            }
        }

        FDInfo[int] directoryMap; // map every watch descriptor to a directory
    }

    private this(int fd) {
        this.fd = fd;
    }

    ~this() {
        if (fd) {
            foreach (fdinfo; directoryMap.byValue) {
                if (fdinfo.watched)
                    inotify_rm_watch(fd, fdinfo.wd);
            }
            close(fd);
        }
    }

    /** Add a path to watch for events.
     *
     * Params:
     *  path = path to watch
     *  events = events to watch for. See man inotify and core.sys.linux.sys.inotify.
     *
     * Returns: true if the path was successfully added.
     */
    bool watch(Path path, uint events = ContentEvents) {
        const wd = inotify_add_watch(fd, path.toStringz, events);
        if (wd != -1) {
            const fc = fcntl(fd, F_SETFD, FD_CLOEXEC);
            if (fc != -1) {
                directoryMap[wd] = FDInfo(wd, true, path);
                return true;
            }
        }

        return false;
    }

    ///
    bool watch(string p, uint events = ContentEvents) {
        return watch(Path(p));
    }

    private static bool allFiles(string p) {
        return true;
    }

    /** Recursively add the path and all its subdirectories and files to be watched.
     *
     * Params:
     *  pred = only those files and directories that `pred` returns true for are watched, by default every file/directory.
     *  root = directory to watch together with its content and subdirectories.
     *  events = events to watch for. See man inotify and core.sys.linux.sys.inotify.
     *
     * Returns: paths that failed to be added.
     */
    AbsolutePath[] watchRecurse(Path root, uint events = ContentEvents,
            bool delegate(string) pred = toDelegate(&allFiles)) {
        import std.algorithm : filter;
        import my.file : existsAnd;
        import my.set;

        auto failed = appender!(AbsolutePath[])();

        if (!watch(root, events)) {
            failed.put(AbsolutePath(root));
        }

        if (!existsAnd!isDir(root)) {
            return failed.data;
        }

        auto dirs = [AbsolutePath(root)];
        Set!AbsolutePath visited;
        while (!dirs.empty) {
            auto front = dirs[0];
            dirs = dirs[1 .. $];
            if (front in visited)
                continue;
            visited.add(front);

            try {
                foreach (p; dirEntries(front, SpanMode.shallow).filter!(a => pred(a.name))) {
                    if (!watch(Path(p.name), events)) {
                        failed.put(AbsolutePath(p.name));
                    }
                    if (existsAnd!isDir(Path(p.name))) {
                        dirs ~= AbsolutePath(p.name);
                    }
                }
            } catch (Exception e) {
                () @trusted { logger.trace(e); }();
                logger.trace(e.msg);
                failed.put(AbsolutePath(front));
            }
        }

        return failed.data;
    }

    ///
    AbsolutePath[] watchRecurse(string root, uint events = ContentEvents,
            bool delegate(string) pred = toDelegate(&allFiles)) {
        return watchRecurse(Path(root), events, pred);
    }

    /** The events that have occured since last query.
     *
     * Params:
     *  timeout = max time to wait for events.
     *
     * Returns: the events that has occured to the watched paths.
     */
    FileChangeEvent[] getEvents(Duration timeout = Duration.zero) {
        import std.algorithm : min;

        FileChangeEvent[] events;
        if (!fd)
            return events;

        pollfd pfd;
        pfd.fd = fd;
        pfd.events = POLLIN;
        const code = poll(&pfd, 1, cast(int) min(int.max, timeout.total!"msecs"));

        if (code < 0) {
            throw new Exception("Failed to poll events. Error code " ~ errno.to!string);
        } else if (code == 0) {
            // timeout triggered
            return events;
        } else if ((pfd.revents & POLLNVAL) != 0) {
            throw new Exception("Failed to poll events. File descriptor not open " ~ fd.to!string);
        }

        const receivedBytes = read(fd, eventBuffer.ptr, eventBuffer.length);
        int i = 0;
        AbsolutePath[uint] cookie;
        while (true) {
            auto info = cast(inotify_event*)(eventBuffer.ptr + i);

            if (info.wd !in directoryMap)
                continue;

            auto fname = () {
                string fileName = info.name.ptr.fromStringz.idup;
                return AbsolutePath(buildPath(directoryMap[info.wd].path, fileName));
            }();

            if ((info.mask & IN_MOVED_TO) == 0) {
                if (auto v = info.cookie in cookie) {
                    events ~= FileChangeEvent(Event.Delete(*v));
                    cookie.remove(info.cookie);
                }
            }

            if ((info.mask & IN_ACCESS) != 0) {
                events ~= FileChangeEvent(Event.Access(fname));
            }

            if ((info.mask & IN_ATTRIB) != 0) {
                events ~= FileChangeEvent(Event.Attribute(fname));
            }

            if ((info.mask & IN_CLOSE_WRITE) != 0) {
                events ~= FileChangeEvent(Event.CloseWrite(fname));
            }

            if ((info.mask & IN_CLOSE_NOWRITE) != 0) {
                events ~= FileChangeEvent(Event.CloseNoWrite(fname));
            }

            if ((info.mask & IN_CREATE) != 0) {
                events ~= FileChangeEvent(Event.Create(fname));
            }

            if ((info.mask & IN_DELETE) != 0) {
                events ~= FileChangeEvent(Event.Delete(fname));
            }

            if ((info.mask & IN_DELETE_SELF) != 0) {
                // must go via the mapping or there may be trailing junk in fname.
                events ~= FileChangeEvent(Event.DeleteSelf(directoryMap[info.wd].path.AbsolutePath));
            }

            if ((info.mask & IN_MODIFY) != 0) {
                events ~= FileChangeEvent(Event.Modify(fname));
            }

            if ((info.mask & IN_MOVE_SELF) != 0) {
                // must go via the mapping or there may be trailing junk in fname.
                events ~= FileChangeEvent(Event.MoveSelf(directoryMap[info.wd].path.AbsolutePath));
            }

            if ((info.mask & IN_MOVED_FROM) != 0) {
                cookie[info.cookie] = fname;
            }

            if ((info.mask & IN_MOVED_TO) != 0) {
                if (auto v = info.cookie in cookie) {
                    events ~= FileChangeEvent(Event.Rename(*v, fname));
                    cookie.remove(info.cookie);
                } else {
                    events ~= FileChangeEvent(Event.Create(fname));
                }
            }

            if ((info.mask & IN_DELETE_SELF) != 0 || (info.mask & IN_MOVE_SELF) != 0) {
                inotify_rm_watch(fd, info.wd);
                directoryMap[info.wd].watched = false;
            }

            i += inotify_event.sizeof + info.len;

            if (i >= receivedBytes)
                break;
        }

        foreach (c; cookie.byValue) {
            events ~= FileChangeEvent(Event.Delete(AbsolutePath(c)));
        }

        return events;
    }
}

///
unittest {
    import core.thread;

    if (exists("test"))
        rmdirRecurse("test");
    scope (exit) {
        if (exists("test"))
            rmdirRecurse("test");
    }

    auto watcher = fileWatch();

    mkdir("test");
    assert(watcher.watch("test"));

    write("test/a.txt", "abc");
    auto ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test/a.txt"));
            return true;
        }));

    append("test/a.txt", "def");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Modify x) {
            assert(x.path == AbsolutePath("test/a.txt"));
            return true;
        }));

    rename("test/a.txt", "test/b.txt");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Rename x) {
            assert(x.from == AbsolutePath("test/a.txt"));
            assert(x.to == AbsolutePath("test/b.txt"));
            return true;
        }));

    remove("test/b.txt");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Delete x) {
            assert(x.path == AbsolutePath("test/b.txt"));
            return true;
        }));

    rmdirRecurse("test");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.DeleteSelf x) {
            assert(x.path == AbsolutePath("test"));
            return true;
        }));
}

///
unittest {
    import std.algorithm : canFind;

    if (exists("test2"))
        rmdirRecurse("test2");
    if (exists("test3"))
        rmdirRecurse("test3");
    scope (exit) {
        if (exists("test2"))
            rmdirRecurse("test2");
        if (exists("test3"))
            rmdirRecurse("test3");
    }

    auto watcher = fileWatch();
    mkdir("test2");
    assert(watcher.watchRecurse("test2").length == 0);

    write("test2/a.txt", "abc");
    auto ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 3);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/a.txt"));
            return true;
        }));
    assert(ev[1].tryMatch!((Event.Modify x) {
            assert(x.path == AbsolutePath("test2/a.txt"));
            return true;
        }));
    assert(ev[2].tryMatch!((Event.CloseWrite x) {
            assert(x.path == AbsolutePath("test2/a.txt"));
            return true;
        }));

    rename("test2/a.txt", "./testfile-a.txt");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Delete x) {
            assert(x.path == AbsolutePath("test2/a.txt"));
            return true;
        }));

    rename("./testfile-a.txt", "test2/b.txt");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/b.txt"));
            return true;
        }));

    remove("test2/b.txt");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Delete x) {
            assert(x.path == AbsolutePath("test2/b.txt"));
            return true;
        }));

    mkdir("test2/mydir");
    rmdir("test2/mydir");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 2);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/mydir"));
            return true;
        }));
    assert(ev[1].tryMatch!((Event.Delete x) {
            assert(x.path == AbsolutePath("test2/mydir"));
            return true;
        }));

    // test for creation, modification, removal of subdirectory
    mkdir("test2/subdir");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/subdir"));
            // add the created directory to be watched
            watcher.watchRecurse(x.path);
            return true;
        }));

    write("test2/subdir/c.txt", "abc");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 3);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/subdir/c.txt"));
            return true;
        }));

    write("test2/subdir/c.txt", "\nabc");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 2);
    assert(ev[0].tryMatch!((Event.Modify x) {
            assert(x.path == AbsolutePath("test2/subdir/c.txt"));
            return true;
        }));

    rmdirRecurse("test2/subdir");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 3);
    foreach (e; ev) {
        assert(ev[0].tryMatch!((Event.Delete x) {
                assert(canFind([
                    AbsolutePath("test2/subdir/c.txt"),
                    AbsolutePath("test2/subdir")
                ], x.path));
                return true;
            }, (Event.DeleteSelf x) {
                assert(x.path == AbsolutePath("test2/subdir"));
                return true;
            }));
    }

    // removal of watched folder
    rmdirRecurse("test2");
    ev = watcher.getEvents(5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.DeleteSelf x) {
            assert(x.path == AbsolutePath("test2"));
            return true;
        }));
}

struct MonitorResult {
    enum Kind {
        Access,
        Attribute,
        CloseWrite,
        CloseNoWrite,
        Create,
        Delete,
        DeleteSelf,
        Modify,
        MoveSelf,
        Rename,
        Open,
    }

    Kind kind;
    AbsolutePath path;
}

/** Monitor root's for filesystem changes which create/remove/modify
 * files/directories.
 */
struct Monitor {
    import std.array : appender;
    import std.file : isDir;
    import std.utf : UTFException;
    import my.filter : GlobFilter;
    import my.fswatch;
    import my.set;
    import sumtype;

    private {
        Set!AbsolutePath roots;
        FileWatch fw;
        GlobFilter fileFilter;
        uint events;

        // roots that has been removed that may be re-added later on. the user
        // expects them to trigger events.
        Set!AbsolutePath monitorRoots;
    }

    /**
     * Params:
     *  roots = directories to recursively monitor
     */
    this(AbsolutePath[] roots, GlobFilter fileFilter, uint events = ContentEvents) {
        this.roots = toSet(roots);
        this.fileFilter = fileFilter;
        this.events = events;

        auto app = appender!(AbsolutePath[])();
        fw = fileWatch();
        foreach (r; roots) {
            app.put(fw.watchRecurse(r, events, (a) {
                    return isInteresting(fileFilter, a);
                }));
        }

        logger.trace(!app.data.empty, "unable to watch ", app.data);
    }

    static bool isInteresting(GlobFilter fileFilter, string p) nothrow {
        import my.file;

        try {
            const ap = AbsolutePath(p);

            if (existsAnd!isDir(ap)) {
                return true;
            }
            return fileFilter.match(ap);
        } catch (Exception e) {
            collectException(logger.trace(e.msg));
        }

        return false;
    }

    /** Wait up to `timeout` for an event to occur for the monitored `roots`.
     *
     * Params:
     *  timeout = how long to wait for the event
     */
    MonitorResult[] wait(Duration timeout) {
        import std.array : array;
        import std.algorithm : canFind, startsWith, filter;

        auto rval = appender!(MonitorResult[])();

        {
            auto rm = appender!(AbsolutePath[])();
            foreach (a; monitorRoots.toRange.filter!(a => exists(a))) {
                fw.watchRecurse(a, events, a => isInteresting(fileFilter, a));
                rm.put(a);
                rval.put(MonitorResult(MonitorResult.Kind.Create, a));
            }
            foreach (a; rm.data) {
                monitorRoots.remove(a);
            }
        }

        if (!rval.data.empty) {
            // collect whatever events that happend to have queued up together
            // with the artifically created.
            timeout = Duration.zero;
        }

        try {
            foreach (e; fw.getEvents(timeout)) {
                e.match!((Event.Access x) {
                    rval.put(MonitorResult(MonitorResult.Kind.Access, x.path));
                }, (Event.Attribute x) {
                    rval.put(MonitorResult(MonitorResult.Kind.Attribute, x.path));
                }, (Event.CloseWrite x) {
                    rval.put(MonitorResult(MonitorResult.Kind.CloseWrite, x.path));
                }, (Event.CloseNoWrite x) {
                    rval.put(MonitorResult(MonitorResult.Kind.CloseNoWrite, x.path));
                }, (Event.Create x) {
                    rval.put(MonitorResult(MonitorResult.Kind.Create, x.path));
                    fw.watchRecurse(x.path, events, a => isInteresting(fileFilter, a));
                }, (Event.Modify x) {
                    rval.put(MonitorResult(MonitorResult.Kind.Modify, x.path));
                }, (Event.MoveSelf x) {
                    rval.put(MonitorResult(MonitorResult.Kind.MoveSelf, x.path));
                    fw.watchRecurse(x.path, events, a => isInteresting(fileFilter, a));

                    if (x.path in roots) {
                        monitorRoots.add(x.path);
                    }
                }, (Event.Delete x) {
                    rval.put(MonitorResult(MonitorResult.Kind.Delete, x.path));
                }, (Event.DeleteSelf x) {
                    rval.put(MonitorResult(MonitorResult.Kind.DeleteSelf, x.path));

                    if (x.path in roots) {
                        monitorRoots.add(x.path);
                    }
                }, (Event.Rename x) {
                    rval.put(MonitorResult(MonitorResult.Kind.Rename, x.to));
                }, (Event.Open x) {
                    rval.put(MonitorResult(MonitorResult.Kind.Open, x.path));
                },);
            }
        } catch (Exception e) {
            logger.trace(e.msg);
        }

        return rval.data.filter!(a => fileFilter.match(a.path)).array;
    }

    /** Collects events from the monitored `roots` over a period.
     *
     * Params:
     *  collectTime = for how long to clear the queue
     */
    MonitorResult[] collect(Duration collectTime) {
        import std.algorithm : max, min;
        import std.datetime : Clock;

        auto rval = appender!(MonitorResult[])();
        const stopAt = Clock.currTime + collectTime;

        do {
            collectTime = max(stopAt - Clock.currTime, 1.dur!"msecs");
            if (!monitorRoots.empty) {
                // must use a hybrid approach of poll + inotify because if a
                // root is added it will only be detected by polling.
                collectTime = min(10.dur!"msecs", collectTime);
            }

            rval.put(wait(collectTime));
        }
        while (Clock.currTime < stopAt);

        return rval.data;
    }
}

@("shall re-apply monitoring for a file that is removed")
unittest {
    import my.filter : GlobFilter;
    import my.test;

    auto ta = makeTestArea("re-apply monitoring");
    const testTxt = ta.inSandbox("test.txt").AbsolutePath;

    write(testTxt, "abc");
    auto fw = Monitor([testTxt], GlobFilter(["*"], null));
    write(testTxt, "abcc");
    assert(!fw.wait(Duration.zero).empty);

    remove(testTxt);
    assert(!fw.wait(Duration.zero).empty);

    write(testTxt, "abcc");
    assert(!fw.wait(Duration.zero).empty);
}
