/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.database.type;

import core.time : Duration;
import std.datetime : SysTime;

import my.named_type;
import sumtype;

import dextool.type : AbsolutePath, Path;
import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.database.schema : MarkedMutantTbl;
public import dextool.plugin.mutate.backend.database.schema : MutantTimeoutCtxTbl;

alias MutantTimeoutCtx = MutantTimeoutCtxTbl;

@safe:

/// Primary key in the mutation table
alias MutationId = NamedType!(long, Tag!"MutationId", 0, Comparable, Hashable, ConvertStringable);

/// Primary key for mutation status
struct MutationStatusId {
    long value;
    alias value this;
}

/// Primary key in the files table
struct FileId {
    long value;
    alias value this;
}

/// Primary key in the test_case table
struct TestCaseId {
    long value;
    alias value this;
}

/// Primary key for mutation schematas.
struct SchemataId {
    long value;
    alias value this;
}

/// Primary key for a schemata fragment.
struct SchemataFragmentId {
    long value;
    alias value this;
}

struct MutationEntry {
    MutationId id;
    Path file;
    SourceLoc sloc;
    MutationPoint mp;
    Duration timeSpentMutating;
    Language lang;
}

struct NextMutationEntry {
    import std.typecons : Nullable;

    enum Status {
        /// Mutant retrieved.
        ok,
        /// All mutants tested.
        done,
    }

    Status st;
    Nullable!MutationEntry entry;
}

struct MutationPointEntry {
    MutationPoint mp;
    Path file;
    /// Start of the mutation point.
    SourceLoc sloc;
    /// End of the mutation point.
    SourceLoc slocEnd;
}

/// The source code mutations for a mutation point.
struct MutationPointEntry2 {
    Path file;
    Offset offset;
    /// Start of the mutation point.
    SourceLoc sloc;
    /// End of the mutation point.
    SourceLoc slocEnd;
    CodeMutant[] cms;

    void put(CodeMutant m) @safe pure nothrow {
        cms ~= m;
    }
}

/// Report about mutants of a specific kind(s).
struct MutationReportEntry {
    ///
    long count;
    /// Test time spent on the mutants.
    Duration time;
}

/// Mutants that are tagged with nomut of a specific kind(s).
struct MetadataNoMutEntry {
    ///
    long count;
}

struct MutantInfo {
    MutationId id;
    Mutation.Status status;
    Mutation.Kind kind;
    SourceLoc sloc;
}

struct TestCaseInfo {
    /// The sum on the execution time of killing the mutants.
    Duration time;
    ///
    long killedMutants;
}

/// What mutants a test case killed.
struct TestCaseInfo2 {
    TestCase name;
    MutationId[] killed;
}

struct MutationStatusTime {
    import std.datetime : SysTime;

    MutationStatusId id;
    SysTime updated;
}

struct MutationStatus {
    import std.datetime : SysTime;
    import std.typecons : Nullable;

    MutationStatusId statusId;
    Mutation.Status status;
    MutantTestCount testCnt;
    SysTime updated;
    Nullable!SysTime added;
}

/// Metadata about a line in a file.
struct LineMetadata {
    FileId id;
    uint line;
    LineAttr attr;

    this(FileId fid, uint line) {
        this(fid, line, LineAttr.init);
    }

    this(FileId fid, uint line, LineAttr attr) {
        this.id = fid;
        this.line = line;
        this.attr = attr;
    }

    void set(NoMut a) @trusted pure nothrow @nogc {
        attr = LineAttr(a);
    }

    bool isNoMut() @safe pure nothrow const @nogc {
        return attr.match!((NoMetadata a) => false, (NoMut a) => true);
    }
}

struct NoMetadata {
}

/// A mutation suppression with optional tag and comment.
struct NoMut {
    string tag;
    string comment;
}

/// Metadata attributes that may be attached to a mutant.
alias MutantAttr = SumType!(NoMetadata, NoMut);

/// Metadata attributes that may be attached to a line.
alias LineAttr = SumType!(NoMetadata, NoMut);

/// Metadata about a mutant.
struct MutantMetaData {
    import std.range : isOutputRange;

    MutationId id;
    MutantAttr attr;

    this(MutationId id) {
        this(id, MutantAttr.init);
    }

    this(MutationId id, MutantAttr attr) {
        this.id = id;
        this.attr = attr;
    }

    void set(NoMut a) @trusted pure nothrow @nogc {
        attr = MutantAttr(a);
    }

    bool isNoMut() @safe pure nothrow const @nogc {
        return attr.match!((NoMetadata a) => false, (NoMut a) => true);
    }

    string kindToString() @safe pure const {
        import std.array : appender;
        import std.format : FormatSpec;

        auto buf = appender!string;
        kindToString(buf);
        return buf.data;
    }

    void kindToString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.range : put;

        attr.match!((NoMetadata a) {}, (NoMut a) => put(w, "nomut"));
    }

    import std.range : isOutputRange;

    string toString() @safe pure const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        kindToString(w);
    }
}

struct Rationale {
    string payload;
    alias payload this;
}

struct MarkedMutant {
    MutationStatusId statusId;
    /// Checksum of the marked mutant.
    Checksum statusChecksum;

    MutationId mutationId;

    SourceLoc sloc;
    Path path;

    /// The status it should always be changed to.
    Mutation.Status toStatus;

    /// Time when the mutant where marked.
    SysTime time;

    Rationale rationale;

    string mutText;
}

/// A fragment of a schemata which is one application.
struct SchemataFragment {
    Path file;
    Offset offset;
    const(ubyte)[] text;
}

struct Schemata {
    SchemataId id;

    /// Sorted in the order they should be applied.
    SchemataFragment[] fragments;
}
