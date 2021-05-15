/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.type;

import core.time : Duration;

import my.hash : Checksum128;
import my.named_type;
public import dextool.plugin.mutate.backend.database.type : MutantAttr, MutantMetaData;

@safe:

alias Checksum = Checksum128;

/// Used to replace invalid UTF-8 characters.
immutable invalidUtf8 = "[invalid utf8]";

/** A mutation point for a specific file.
 *
 * TODO: shouldn't this have the file ID?
 *
 * See: definitions.md for more information
 */
struct MutationPoint {
    Offset offset;
    Mutation[] mutations;

    bool opEquals()(auto ref const S s) @safe pure nothrow const @nogc {
        return offset == s.offset && mutations == s.mutations;
    }
}

/// Offset range. It is a closed->open set.
struct Offset {
    import std.algorithm : min, max;

    // TODO: fix bug somewhere which mean that begin > end.
    uint begin;
    uint end;

    /// If the offset has size zero.
    bool isZero() @safe pure nothrow const @nogc {
        return begin >= end;
    }

    uint length() @safe pure nothrow const @nogc {
        if (isZero)
            return 0;
        return end - begin;
    }

    /// Check if offsets intersect.
    bool intersect(in Offset y) //in (y.begin <= y.end, "y.begin > y.end")
    //in (begin <= end, "begin > end")
    {
        const x1 = min(begin, end);
        const x2 = max(begin, end);
        const y1 = min(y.begin, y.end);
        const y2 = max(y.begin, y.end);

        return x2 >= y1 && y2 >= x1;
    }

    /// Check if offsets overlap.
    bool overlap(in Offset y) //in (y.begin <= y.end, "y.begin > y.end")
    //in (begin <= end, "begin > end")
    {
        static bool test(Offset y, uint p) {
            const y1 = min(y.begin, y.end);
            const y2 = max(y.begin, y.end);
            return y1 <= p && p < y2;
        }
        //       a--------a
        // true:     b--------b
        // true:    c--c
        const t0 = test(this, y.begin);
        const t1 = test(this, y.end);

        return ((t0 || t1) && (t0 != t1)) || (t0 && t1);
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        auto a = begin.hashOf();
        return end.hashOf(a); // mixing two hash values
    }

    bool opEquals()(auto ref const typeof(this) s) const {
        return s.begin == begin && s.end == end;
    }

    int opCmp(ref const typeof(this) rhs) @safe pure nothrow const @nogc {
        // return -1 if "this" is less than rhs, 1 if bigger and zero equal
        if (begin < rhs.begin)
            return -1;
        if (begin > rhs.begin)
            return 1;
        if (end < rhs.end)
            return -1;
        if (end > rhs.end)
            return 1;
        return 0;
    }
}

/// Location in the source code.
struct SourceLoc {
    uint line;
    uint column;

    int opCmp(ref const typeof(this) rhs) @safe pure nothrow const @nogc {
        // return -1 if "this" is less than rhs, 1 if bigger and zero equal
        if (line < rhs.line)
            return -1;
        if (line > rhs.line)
            return 1;
        if (column < rhs.column)
            return -1;
        if (column > rhs.column)
            return 1;
        return 0;
    }
}

struct SourceLocRange {
    SourceLoc begin;
    SourceLoc end;

    int opCmp(ref const typeof(this) rhs) const {
        // return -1 if "this" is less than rhs, 1 if bigger and zero equal
        auto cb = begin.opCmp(rhs.begin);
        if (cb != 0)
            return cb;
        auto ce = end.opCmp(rhs.end);
        if (ce != 0)
            return ce;
        return 0;
    }
}

/// A possible mutation.
struct Mutation {
    /// States what kind of mutations that can be performed on this mutation point.
    // ONLY ADD NEW ITEMS TO THE END
    enum Kind : uint {
        /// the kind is not initialized thus can only ignore the point
        none,
        /// Relational operator replacement
        rorLT,
        rorLE,
        rorGT,
        rorGE,
        rorEQ,
        rorNE,
        /// Logical connector replacement
        lcrAnd,
        lcrOr,
        /// Arithmetic operator replacement
        aorMul,
        aorDiv,
        aorRem,
        aorAdd,
        aorSub,
        aorMulAssign,
        aorDivAssign,
        aorRemAssign,
        aorAddAssign,
        aorSubAssign,
        /// Unary operator insert on an lvalue
        uoiPostInc,
        uoiPostDec,
        // these work for rvalue
        uoiPreInc, // unused
        uoiPreDec, // unused
        uoiAddress, // unused
        uoiIndirection, // unused
        uoiPositive, // unused
        uoiNegative, // unused
        uoiComplement, // unused
        uoiNegation,
        uoiSizeof_, // unused
        /// Absolute value replacement
        absPos,
        absNeg,
        absZero,
        /// statement deletion
        stmtDel,
        /// Conditional Operator Replacement (reduced set)
        corAnd, // unused
        corOr, // unused
        corFalse, // unused
        corLhs, // unused
        corRhs, // unused
        corEQ, // unused
        corNE, // unused
        corTrue, // unused
        /// Relational operator replacement
        rorTrue,
        rorFalse,
        /// Decision/Condition Coverage
        dcrTrue,
        dcrFalse,
        dcrBomb, // unused
        /// Decision/Condition Requirement
        dcrCaseDel, // unused
        /// Relational operator replacement for pointers
        rorpLT,
        rorpLE,
        rorpGT,
        rorpGE,
        rorpEQ,
        rorpNE,
        /// Logical Operator Replacement Bit-wise (lcrb)
        lcrbAnd,
        lcrbOr,
        lcrbAndAssign,
        lcrbOrAssign,
        lcrbLhs,
        lcrbRhs,
        /// Logical connector replacement
        lcrLhs,
        lcrRhs,
        lcrTrue,
        lcrFalse,
        /// Arithmetic operator replacement
        aorLhs,
        aorRhs,
        // uoi
        uoiDel,
        // dcr for return types
        dcrReturnTrue, // unused
        dcrReturnFalse, // unused
        // aors variant
        aorsMul,
        aorsDiv,
        aorsAdd,
        aorsSub,
        aorsMulAssign,
        aorsDivAssign,
        aorsAddAssign,
        aorsSubAssign,
    }

    /// The status of a mutant.
    enum Status : ubyte {
        /// the mutation isn't tested
        unknown,
        /// killed by the test suite
        killed,
        /// not killed by the test suite
        alive,
        /// the mutation resulted in invalid code that didn't compile
        killedByCompiler,
        /// the mutant resulted in the test suite/sut reaching the timeout threshold
        timeout,
        /// not covered by the tests
        noCoverage,
        ///
        equivalent
    }

    Kind kind;
    Status status;
}

/// The unique checksum for a schemata.
struct SchemataChecksum {
    Checksum value;
}

/** The checksum that uniquely identify the mutation done in the source code.
 *
 * Multiple mutants can end up resulting in the same change in the source code.
 */
struct CodeChecksum {
    Checksum value;
    alias value this;
}

/// The mutant coupled to the source code mutant that is injected.
struct CodeMutant {
    CodeChecksum id;
    Mutation mut;

    bool opEquals(const typeof(this) s) const {
        return id == s.id;
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        return id.toHash;
    }
}

/// A test case from the test suite that is executed on mutants.
struct TestCase {
    /// The name of the test case as extracted from the test suite.
    string name;

    /// A location identifier intended to be presented to the user.
    string location;

    this(string name) @safe pure nothrow @nogc scope {
        this(name, null);
    }

    this(string name, string loc) @safe pure nothrow @nogc scope {
        this.name = name;
        this.location = loc;
    }

    int opCmp(ref const typeof(this) s) @safe pure nothrow const @nogc scope {
        if (name < s.name)
            return -1;
        else if (name > s.name)
            return 1;
        else if (location < s.location)
            return -1;
        else if (location > s.location)
            return 1;

        return 0;
    }

    bool opEquals(ref const typeof(this) s) @safe pure nothrow const @nogc scope {
        return name == s.name && location == s.location;
    }

    size_t toHash() @safe nothrow const {
        return typeid(string).getHash(&name) + typeid(string).getHash(&location);
    }

    string toString() @safe pure const nothrow {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    import std.range : isOutputRange;

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.range : put;

        if (location.length != 0) {
            put(w, location);
            put(w, ":");
        }
        put(w, name);
    }
}

/// The language a file or mutant is.
enum Language {
    /// the default is assumed to be c++
    assumeCpp,
    ///
    cpp,
    ///
    c
}

/// Test Group criterias.
struct TestGroup {
    import std.regex : Regex, regex;

    string description;
    string name;

    /// What the user configured as regex. Useful when e.g. generating reports
    /// for a user.
    string userInput;
    /// The compiled regex.
    Regex!char re;

    this(string name, string desc, string r) {
        this.name = name;
        description = desc;
        userInput = r;
        re = regex(r);
    }

    string toString() @safe pure const {
        import std.format : format;

        return format("TestGroup(%s, %s, %s)", name, description, userInput);
    }

    import std.range : isOutputRange;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;

        formattedWrite(w, "TestGroup(%s, %s, %s)", name, description, userInput);
    }
}

/** A source code token.
 *
 * The source can contain invalid UTF-8 chars therefor every token has to be
 * validated. Otherwise it isn't possible to generate a report.
 */
struct Token {
    import std.format : format;
    import clang.c.Index : CXTokenKind;

    // TODO: this should be a language agnostic type when more languages are
    // added in the future.
    CXTokenKind kind;
    Offset offset;
    SourceLoc loc;
    SourceLoc locEnd;
    string spelling;

    this(CXTokenKind kind, Offset offset, SourceLoc loc, SourceLoc locEnd, string spelling) {
        this.kind = kind;
        this.offset = offset;
        this.loc = loc;
        this.locEnd = locEnd;

        try {
            import std.utf : validate;

            validate(spelling);
            this.spelling = spelling;
        } catch (Exception e) {
            this.spelling = invalidUtf8;
        }
    }

    string toId() @safe const {
        return format("%s-%s", offset.begin, offset.end);
    }

    string toName() @safe const {
        import std.conv : to;

        return kind.to!string;
    }

    int opCmp(ref const typeof(this) s) const @safe {
        if (offset.begin > s.offset.begin)
            return 1;
        if (offset.begin < s.offset.begin)
            return -1;
        if (offset.end > s.offset.end)
            return 1;
        if (offset.end < s.offset.end)
            return -1;
        return 0;
    }
}

@("shall be possible to construct in @safe")
@safe unittest {
    import clang.c.Index : CXTokenKind;

    auto tok = Token(CXTokenKind.comment, Offset(1, 2), SourceLoc(1, 2), SourceLoc(1, 2), "smurf");
}

alias ExitStatus = NamedType!(int, Tag!"ExitStatus", int.init, TagStringable);

/// Profile of what a mutant spent time on to collect a status.
struct MutantTimeProfile {
    /// Time it took to compile the mutant.
    Duration compile;

    /// Time it took to execute the test suite.
    Duration test;

    this(Duration compile, Duration test) @safe pure nothrow @nogc {
        this.compile = compile;
        this.test = test;
    }

    /// Returns: the sum of all the profile times.
    Duration sum() @safe pure nothrow const @nogc {
        return compile + test;
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

        formattedWrite(w, "%s compile:(%s) test:(%s)", sum, compile, test);
    }
}
