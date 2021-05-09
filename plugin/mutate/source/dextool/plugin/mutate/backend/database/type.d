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
import my.hash : Checksum64;
import sumtype;

import dextool.type : AbsolutePath, Path;
import dextool.plugin.mutate.backend.type;

public import dextool.plugin.mutate.backend.database.schema : MutantTimeoutCtxTbl;
public import dextool.plugin.mutate.backend.type : MutantTimeProfile;

@safe:

/// The context (state) of how the testing of the timeout mutants are going.
alias MutantTimeoutCtx = MutantTimeoutCtxTbl;

/// Primary key in the mutation table
alias MutationId = NamedType!(long, Tag!"MutationId", 0, Comparable, Hashable, ConvertStringable);

/// Primary key for mutation status
alias MutationStatusId = NamedType!(long, Tag!"MutationStatusId", long.init,
        Comparable, Hashable, ConvertStringable);

/// Primary key in the files table
alias FileId = NamedType!(long, Tag!"FileId", long.init, Comparable, Hashable, TagStringable);

/// Primary key in the test files table
alias TestFileId = NamedType!(long, Tag!"TestFileId", long.init, Comparable,
        Hashable, TagStringable);

/// Primary key in the test_case table
alias TestCaseId = NamedType!(long, Tag!"TestCaseId", long.init, Comparable,
        Hashable, TagStringable);

/// Primary key for mutation schematas.
alias SchemataId = NamedType!(long, Tag!"SchemataId", long.init, Comparable,
        Hashable, TagStringable);

/// Primary key for a schemata fragment.
alias SchemataFragmentId = NamedType!(long, Tag!"SchemataFragmentId",
        long.init, Comparable, Hashable, TagStringable);

struct MutationEntry {
    MutationId id;
    Path file;
    SourceLoc sloc;
    MutationPoint mp;
    MutantTimeProfile profile;
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
    MutantTimeProfile time;
}

/// Mutants that are tagged with nomut of a specific kind(s).
struct MetadataNoMutEntry {
    ///
    long count;
}

struct MutantInfo {
    MutationId id;
    Mutation.Status status;
    ExitStatus ecode;
    Mutation.Kind kind;
    SourceLoc sloc;
}

struct TestCaseInfo {
    /// The sum on the execution time of killing the mutants.
    MutantTimeProfile time;

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

alias MutantPrio = NamedType!(long, Tag!"MutantPriority", long.init, TagStringable);

struct MutationStatus {
    import std.datetime : SysTime;
    import std.typecons : Nullable;

    MutationStatusId statusId;
    Mutation.Status status;
    MutantPrio prio;
    SysTime updated;
    Nullable!SysTime added;
    ExitStatus exitStatus;
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

alias Rationale = NamedType!(string, Tag!"Rationale", string.init, TagStringable);

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

struct TestCmdRuntime {
    SysTime timeStamp;

    /// The execution time of the test suite.
    Duration runtime;
}

struct MutationScore {
    SysTime timeStamp;
    NamedType!(double, Tag!"MutationScore", 0.0, TagStringable) score;
}

alias TestFilePath = NamedType!(Path, Tag!"TestFilePath", Path.init, Hashable, TagStringable);
alias TestFileChecksum = NamedType!(Checksum, Tag!"TestFileChecksum",
        Checksum.init, TagStringable, Hashable);

struct TestFile {
    TestFilePath file;

    /// Checksum of the content.
    TestFileChecksum checksum;

    /// Last time the file was changed.
    SysTime timeStamp;
}

alias CoverageRegionId = NamedType!(long, Tag!"CoverageRegionId", long.init,
        Comparable, Hashable, ConvertStringable);
struct CovRegion {
    CoverageRegionId id;
    Offset region;
}

/// A file that a root is dependent on.
struct DepFile {
    Path file;
    Checksum checksum;
}

alias ToolVersion = NamedType!(long, Tag!"ToolVersion", long.init, TagStringable, Comparable);

alias ChecksumTestCmdOriginal = NamedType!(Checksum64,
        Tag!"ChecksumTestCmdOriginal", Checksum64.init, TagStringable);
