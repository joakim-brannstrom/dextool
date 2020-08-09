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
import core.sys.posix.poll : pollfd, poll, POLLIN;
import core.thread : Thread;
import core.time : dur, Duration;
import std.array : appender;
import std.conv : to;
import std.file : DirEntry, isDir, dirEntries, rmdirRecurse, write, append,
    rename, remove, exists, SpanMode, mkdir, rmdir;
import std.path : buildPath;
import std.range : isInputRange;
import std.string : toStringz, fromStringz;

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
enum DefaultEvents = IN_CREATE | IN_DELETE | IN_DELETE_SELF | IN_MODIFY | IN_MOVE_SELF
    | IN_MOVED_FROM | IN_MOVED_TO | IN_ATTRIB | IN_EXCL_UNLINK | IN_CLOSE_WRITE;

/** An instance of a FileWatcher
 */
struct FileWatch {
    private {
        int fd;
        ubyte[1024 * 4] eventBuffer; // 4kb buffer for events
        pollfd pfd;
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
    bool watch(Path path, uint events = DefaultEvents) {
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
    bool watch(string p, uint events = DefaultEvents) {
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
    AbsolutePath[] watchRecurse(alias pred = allFiles)(Path root, uint events = DefaultEvents) {
        import std.algorithm : filter;
        import my.file : existsAnd;

        auto app = appender!(AbsolutePath[])();

        if (!watch(root, events)) {
            app.put(AbsolutePath(root));
        }

        if (existsAnd!isDir(root)) {
            foreach (p; dirEntries(root, SpanMode.depth).filter!(a => pred(a.name))) {
                if (!watch(Path(p.name), events)) {
                    app.put(AbsolutePath(p.name));
                }
            }
        }

        return app.data;
    }

    ///
    AbsolutePath[] watchRecurse(alias pred = allFiles)(string root, uint events = DefaultEvents) {
        return watchRecurse!pred(Path(root), events);
    }

    /// Returns: the events that has occured to the watched paths.
    FileChangeEvent[] getEvents() {
        FileChangeEvent[] events;
        if (!fd)
            return events;

        pfd.fd = fd;
        pfd.events = POLLIN;
        const code = poll(&pfd, 1, 0);
        if (code < 0)
            throw new Exception("Failed to poll events. Error code " ~ errno.to!string);
        else if (code == 0)
            return events;

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

    /** Check for events every interval.
     *
     * Params:
     *  interval = how often to check for events.
     *  timeout = max time to wait for events.
     */
    FileChangeEvent[] wait(Duration interval = 10.dur!"msecs", Duration timeout = 52.dur!"weeks") {
        import std.datetime : Clock;
        import core.thread : Thread;

        const stopAt = Clock.currTime + timeout;
        FileChangeEvent[] ret;

        while ((ret = getEvents()).length == 0) {
            if (Clock.currTime > stopAt)
                break;
            Thread.sleep(interval);
        }

        return ret;
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
    auto ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test/a.txt"));
            return true;
        }));

    append("test/a.txt", "def");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Modify x) {
            assert(x.path == AbsolutePath("test/a.txt"));
            return true;
        }));

    rename("test/a.txt", "test/b.txt");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Rename x) {
            assert(x.from == AbsolutePath("test/a.txt"));
            assert(x.to == AbsolutePath("test/b.txt"));
            return true;
        }));

    remove("test/b.txt");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length > 0);
    assert(ev[0].tryMatch!((Event.Delete x) {
            assert(x.path == AbsolutePath("test/b.txt"));
            return true;
        }));

    rmdirRecurse("test");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
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
    auto ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
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
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Delete x) {
            assert(x.path == AbsolutePath("test2/a.txt"));
            return true;
        }));

    rename("./testfile-a.txt", "test2/b.txt");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/b.txt"));
            return true;
        }));

    remove("test2/b.txt");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Delete x) {
            assert(x.path == AbsolutePath("test2/b.txt"));
            return true;
        }));

    mkdir("test2/mydir");
    rmdir("test2/mydir");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
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
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/subdir"));
            // add the created directory to be watched
            watcher.watchRecurse(x.path);
            return true;
        }));

    write("test2/subdir/c.txt", "abc");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length == 3);
    assert(ev[0].tryMatch!((Event.Create x) {
            assert(x.path == AbsolutePath("test2/subdir/c.txt"));
            return true;
        }));

    write("test2/subdir/c.txt", "\nabc");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length == 2);
    assert(ev[0].tryMatch!((Event.Modify x) {
            assert(x.path == AbsolutePath("test2/subdir/c.txt"));
            return true;
        }));

    rmdirRecurse("test2/subdir");
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
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
    ev = watcher.wait(1.dur!"msecs", 5.dur!"seconds");
    assert(ev.length == 1);
    assert(ev[0].tryMatch!((Event.DeleteSelf x) {
            assert(x.path == AbsolutePath("test2"));
            return true;
        }));
}
