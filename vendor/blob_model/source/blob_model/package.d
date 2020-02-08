/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module blob_model;

version (unittest) {
    import unit_threaded.assertions;
}

struct Uri {
    string value;
    int version_;

    int opCmp(ref const typeof(this) rhs) const {
        import std.string : cmp;

        if (version_ != rhs.version_)
            return version_ - rhs.version_;
        return cmp(value, rhs.value);
    }

    T opCast(T : string)() @safe pure nothrow const @nogc {
        return value;
    }
}

struct Offset {
    size_t value;
    alias value this;
}

struct Interval {
    Offset start;
    Offset end;
    private bool append_;

    invariant {
        assert(start <= end);
    }

    this(Offset s, Offset e) @safe pure nothrow @nogc {
        start = s;
        end = e;
    }

    this(size_t s, size_t e) @safe pure nothrow @nogc {
        this(Offset(s), Offset(e));
    }

    /**Returns: An interval that will always be at the end which mean that if
     * it is e.g. used for an Edit it will be appended to the file.
     */
    static Interval append() @safe pure nothrow @nogc {
        auto r = Interval(0, 0);
        r.append_ = true;
        return r;
    }

    int opCmp(ref const Interval rhs) @safe pure nothrow const @nogc {
        if (start < rhs.start)
            return -1;
        else if (start > rhs.start)
            return 1;
        else if (start == rhs.start && end < rhs.end)
            return -1;
        else if (start == rhs.start && end > rhs.end)
            return 1;

        return 0;
    }

    int opCmp(const int rhs) @safe pure nothrow const @nogc {
        if (start < rhs)
            return -1;
        if (start > rhs)
            return 1;
        return 0;
    }

    import std.range : isOutputRange;

    string toString() @safe pure const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;

        formattedWrite(w, "[%s, %s)", start, end);
    }
}

/** Detect overlap between this interval and other given interval in a
 * half-open coordinate system [start, end)
 *
 * return true in any of the following four situations:
 *     int1   =====    =======
 *     int2  =======  =======
 *
 *     int1  =======  =======
 *     int2    ===      =======
 *
 * return false in any other scenario:
 *     int1  =====       |       =====
 *     int2       =====  |  =====
 *
 * NOTE that in half-open coordinates [start, end)
 *  i1.end == i2.start => Adjacent, but NO overlap
 *
 * Note: This code is copied from the dub package intervaltree.
 * Author: James S. Blachly, MD <james.blachly@gmail.com>
 * Copyright: Copyright (c) 2019 James Blachly
 * License: MIT
*/
bool overlaps(IntervalType1, IntervalType2)(IntervalType1 int1, IntervalType2 int2) @nogc pure @safe nothrow
        if (__traits(hasMember, IntervalType1, "start") && __traits(hasMember, IntervalType1,
            "end") && __traits(hasMember, IntervalType2, "start")
            && __traits(hasMember, IntervalType2, "end")) {
    // DMD cannot inline this
    version (LDC) pragma(inline, true);
    version (GDC) pragma(inline, true);
    // int1   =====    =======
    // int2 =======  =======
    if (int2.start <= int1.start && int1.start < int2.end)
        return true;

    // int1  =======  =======
    // int2   ===      =======
    else if (int1.start <= int2.start && int2.start < int1.end)
        return true;

    // int1  =====        |       =====
    // int2       =====   |  =====
    else
        return false;
}

@("shall detect overlap between intervals")
unittest {
    overlaps(Interval(5, 10), Interval(2, 10)).should == true;
    overlaps(Interval(5, 10), Interval(2, 8)).should == true;

    overlaps(Interval(5, 15), Interval(7, 11)).should == true;
    overlaps(Interval(5, 15), Interval(7, 20)).should == true;

    overlaps(Interval(5, 15), Interval(15, 20)).should == false;
    overlaps(Interval(15, 20), Interval(5, 15)).should == false;
}

struct Location {
    Uri uri;
    Interval interval;
}

/// Unique identifier for the blob.
class BlobIdentifier {
    Uri uri;

    this(Uri uri = Uri.init) @safe pure nothrow @nogc {
        this.uri = uri;
    }
}

/// A uniquely identifiable blob and its content.
class Blob : BlobIdentifier {
    const(ubyte)[] content;

    this(Uri uri = Uri.init, const(ubyte)[] content = (const(ubyte)[]).init) @safe pure nothrow @nogc {
        super(uri);
        this.content = content;
    }

    this(Uri uri, string content) @safe pure nothrow @nogc {
        this(uri, cast(const(ubyte)[]) content);
    }
}

/// Replace `interval` with `content`.
class Edit {
    Interval interval;
    const(ubyte)[] content;

    /**
     * Params:
     * r       = interval to replace
     * content = with this content
     */
    this(Interval r = Interval.init, const(ubyte)[] content = (const(ubyte)[]).init) @safe pure nothrow @nogc {
        this.interval = r;
        this.content = content;
    }

    this(Interval r, string content) @safe pure nothrow @nogc {
        this(r, cast(const(ubyte)[]) content);
    }

}

class BlobEdit {
    BlobIdentifier blob;
    Edit[] edits;

    /**
     *
     * Params:
     * blob  = identifier of the blob being edited
     * edits = ?
     */
    this(BlobIdentifier blob = new BlobIdentifier(), Edit[] edits = Edit[].init) @safe pure nothrow @nogc {
        this.blob = blob;
        this.edits = edits;
    }
}

/** A virtual file system of blobs.
 *
 * Blobs live in a virtual, in-memory system. They are uniquely identified by
 * their URI.
 *
 * A URI contains a version. This mean that a blob can exist in multiple
 * versions. The original is usually version zero.
 */
class BlobVfs {
    private Blob[Uri] blobs;

    /** Open a blob with the same URI and content as `blob` if it doesn't
     * already exist.
     *
     * Params:
     * blob = the blob to add an entry in the cache for.
     */
    bool open(const Blob blob) @safe pure {
        if (auto v = blob.uri in blobs)
            return false;
        blobs[blob.uri] = new Blob(blob.uri, blob.content);
        return true;
    }

    /** Open a blob with the content read from the file system if it doesn't
     * already exist in the VFS.
     */
    Blob openFromFile(const Uri uri) @safe {
        if (auto v = uri in blobs)
            return *v;
        auto b = get(uri);
        open(b);
        return b;
    }

    /** Close a blob in the cache if it exists.
     *
     * Params:
     * id = ?
     */
    bool close(const BlobIdentifier id) @safe pure nothrow {
        if (id.uri in blobs) {
            blobs.remove(id.uri);
            return true;
        }
        return false;
    }

    /** Get the blob matching the URI either from the VFS or the filesystem.
     *
     * If the blob exists in the VFS with the specific version then that is returned.
     *
     * Otherwise the URI is used to try and locate the blob on the filesystem.
     *
     * This function may throw if the URI do not exists in the internal DB and
     * it refers to a file that do not exist on the filesystem.
     */
    Blob get(const Uri uri) @safe {
        if (auto v = uri in blobs)
            return *v;
        return new Blob(uri, rawRead(cast(string) uri));
    }

    /// Returns: if there exists a blob with the URI.
    bool exists(const Uri uri) @safe pure nothrow const @nogc {
        return (uri in blobs) !is null;
    }

    /**
     * Returns: range of the filenames in the VFS.
     */
    auto uris() @safe pure nothrow const @nogc {
        return blobs.byKey;
    }

    /** Apply a stream of edits to a blob.
     *
     * The edits are applied starting from index zero. If there for example are
     * two edits for the same interval the second one will be applied on top of
     * the first one.
     *
     * Params:
     * id    = blob to change
     * edits = changes
     */
    bool change(const BlobIdentifier id, const(Edit)[] edits) @safe pure nothrow {
        return change(id.uri, edits);
    }

    /// ditto
    bool change(const BlobEdit be) @safe pure nothrow {
        return change(be.blob.uri, be.edits);
    }

    /// ditto
    bool change(const Uri uri, const(Edit)[] edits) @safe pure nothrow {
        import std.algorithm : min;
        import std.array : empty, appender;

        auto blob = uri in blobs;
        if (blob is null || edits.length == 0)
            return false;

        .change(*blob, edits);
        return true;
    }
}

/** Modify the blob.
 */
Blob change(Blob blob, const(Edit)[] edits) @safe pure nothrow {
    import std.algorithm : min, filter;
    import std.array : empty, appender;

    foreach (const e; edits.filter!(a => !a.interval.append_)) {
        if (e.interval.start > e.interval.end)
            continue;
        const start = min(e.interval.start, blob.content.length);
        const end = min(e.interval.end, blob.content.length);

        auto app = appender!(const(ubyte)[])();
        app.put(blob.content[0 .. start]);
        app.put(cast(const(ubyte)[]) e.content);
        app.put(blob.content[end .. $]);
        blob.content = app.data;
    }

    foreach (const e; edits.filter!(a => a.interval.append_)) {
        blob.content ~= e.content;
    }

    return blob;
}

/** Merge edits by concatenation when the intervals overlap.
 *
 * This will never remove content from the original, only add to it.
 *
 * TODO: this my be a bit inefficient because it starts by clearing the content
 * and then adding it all back. Maybe there are a more efficient way?
 * It should at least use the allocators.
 */
BlobEdit merge(const Blob blob, Edit[] edits_) @safe pure nothrow {
    import std.algorithm : sort, min, filter;
    import std.array : array, appender;

    auto r = new BlobEdit(new BlobIdentifier(blob.uri));
    const end = blob.content.length;

    // start by clearing all content.
    r.edits = [new Edit(Interval(0, end))];

    // Current position into the original content which is the position to
    // start taking data from. It is continiusly adjusted when the edits are
    // analysed as to cover the last interval of the original content that
    // where used.
    size_t cur = 0;

    auto app = appender!(const(ubyte)[])();
    foreach (const e; edits_.sort!((a, b) => a.interval < b.interval)
            .filter!(a => !a.interval.append_)) {
        // add the original content until this point.
        if (e.interval.start > cur && cur < end) {
            auto ni = Interval(cur, min(e.interval.start, end));
            app.put(blob.content[ni.start .. ni.end]);
            cur = min(e.interval.end, end);
        }
        app.put(e.content);
    }

    if (cur < end) {
        app.put(blob.content[cur .. $]);
    }

    foreach (const e; edits_.filter!(a => a.interval.append_)) {
        app.put(e.content);
    }

    r.edits ~= new Edit(Interval(0, end), app.data);
    return r;
}

@("shall merge multiple edits into two edits")
unittest {
    auto vfs = new BlobVfs;
    auto uri = Uri("my blob");

    vfs.open(new Blob(uri, "0123456789")).should == true;

    {
        // insert at the beginning and two in the middle concatenated
        Edit[] e;
        e ~= new Edit(Interval(2, 5), "def");
        e ~= new Edit(Interval(8, 9), "ghi");
        e ~= new Edit(Interval(2, 5), "abc");
        // prepend
        e ~= new Edit(Interval(0, 0), "start");
        auto m = merge(vfs.get(uri), e);
        vfs.change(m);
    }

    (cast(string) vfs.get(uri).content).should == "start01abcdef567ghi9";
}

private:

// workaround for linking bug
auto workaroundLinkingBug() {
    import std.typecons;

    return typeid(std.typecons.Tuple!(int, double));
}

const(ubyte)[] rawRead(string path) @safe {
    import std.array : appender;
    import std.stdio : File;

    auto fin = File(path);
    auto content = appender!(ubyte[])();
    ubyte[4096] buf;

    while (!fin.eof) {
        auto s = fin.rawRead(buf);
        content.put(s);
    }

    return content.data;
}

@("shall modify a blob when changes are applied")
unittest {
    auto vfs = new BlobVfs;
    const uri = Uri("my blob");

    vfs.open(new Blob(uri, "this is some data")).should == true;

    {
        Edit[] e;
        e ~= new Edit(Interval(Offset(0), Offset(4)), "that drum");
        e ~= new Edit(Interval(Offset(22), Offset(22)), ", big time");
        vfs.change(uri, e);
    }

    (cast(string) vfs.get(uri).content).should == "that drum is some data, big time";
}

@(
        "shall append edits outside of the interval and remove invalid edits when applying changes to the content")
unittest {
    auto vfs = new BlobVfs;
    const uri = Uri("my blob2");

    vfs.open(new Blob(uri, "more data")).should == true;

    {
        Edit[] e;
        e ~= new Edit(Interval(Offset(9), Offset(15)), "edfgh");
        e ~= new Edit(Interval(Offset(999), Offset(1000)), "abcd");
        vfs.change(uri, e);
    }

    (cast(string) vfs.get(uri).content).should == "more dataedfghabcd";
}

@("shall apply edits on top of each other when changing a blob")
unittest {
    auto vfs = new BlobVfs;
    const uri = Uri("my blob2");

    vfs.open(new Blob(uri, "more data")).should == true;

    {
        Edit[] e;
        e ~= new Edit(Interval(Offset(9), Offset(15)), "edfgh");
        e ~= new Edit(Interval(Offset(10), Offset(11)), "e");
        vfs.change(uri, e);
    }

    (cast(string) vfs.get(uri).content).should == "more dataeefgh";
}

@("shall create the blob from a file on the filesystem when the URI do not exist in the VFS")
unittest {
    import std.file : remove;
    import std.stdio : File;

    auto vfs = new BlobVfs;
    const uri = Uri("my_file.txt");
    File(cast(string) uri, "w").write("a string");
    scope (exit)
        remove(cast(string) uri);

    auto b = vfs.get(uri);

    (cast(string) b.content).should == "a string";
}

@("shall handle blobs with the same path but different versions")
unittest {
    auto vfs = new BlobVfs;
    const uri = "my blob";

    {
        vfs.open(new Blob(Uri(uri), "uri version 0")).should == true;
        vfs.open(new Blob(Uri(uri, 1), "uri version 1")).should == true;
    }

    (cast(string) vfs.get(Uri(uri, 0)).content).should == "uri version 0";
    (cast(string) vfs.get(Uri(uri, 1)).content).should == "uri version 1";
}
