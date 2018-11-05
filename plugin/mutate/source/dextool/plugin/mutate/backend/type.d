/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.type;

import dextool.hash : Checksum128, BuildChecksum128, toBytes, toChecksum128;

@safe:

alias Checksum = Checksum128;

/** A mutation point for a specific file.
 *
 * TODO: shouldn't this have the file ID?
 *
 * See: definitions.md for more information
 */
struct MutationPoint {
    Offset offset;
    Mutation[] mutations;

    bool opEquals()(auto ref const S s) const {
        return offset == s.offset && mutations == s.mutations;
    }
}

/// Create mutation ID's from source code mutations.
struct MutationIdFactory {
    import dextool.type : Path;

    Path file;
    Offset offset;
    Checksum cs;

    /// Calculate the unique ID for a specific mutation at this point.
    Checksum128 makeId(const(ubyte)[] mut) @safe pure nothrow const @nogc scope {
        assert(file.length != 0);

        BuildChecksum128 h;
        h.put(cast(const(ubyte)[]) file);
        h.put(cs.c0.toBytes);
        h.put(cs.c1.toBytes);
        h.put(offset.begin.toBytes);
        h.put(offset.end.toBytes);
        h.put(mut);
        return toChecksum128(h);
    }

    /// Create a mutant at this mutation point.
    CodeMutant makeMutant(Mutation m, const(ubyte)[] mut) @safe pure nothrow const @nogc scope {
        assert(file.length != 0);
        auto id = makeId(mut);
        return CodeMutant(CodeChecksum(id), m);
    }
}

/// Offset range. It is a `[)` (closed->open).
struct Offset {
    uint begin;
    uint end;
}

/// Location in the source code.
struct SourceLoc {
    uint line;
    uint column;
}

/// A possible mutation and its status.
struct Mutation {
    /// States what kind of mutations that can be performed on this mutation point.
    // ONLY ADD NEW ITEMS TO THE END
    enum Kind {
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
        uoiPreInc,
        uoiPreDec,
        uoiAddress,
        uoiIndirection,
        uoiPositive,
        uoiNegative,
        uoiComplement,
        uoiNegation,
        uoiSizeof_,
        /// Absolute value replacement
        absPos,
        absNeg,
        absZero,
        /// statement deletion
        stmtDel,
        /// Conditional Operator Replacement (reduced set)
        corAnd,
        corOr,
        corFalse,
        corLhs,
        corRhs,
        corEQ,
        corNE,
        corTrue,
        /// Relational operator replacement
        rorTrue,
        rorFalse,
        /// Decision/Condition Coverage
        dccTrue,
        dccFalse,
        dccBomb,
        /// Decision/Condition Requirement
        dcrCaseDel,
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
    }

    enum Status {
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
    }

    Kind kind;
    Status status;
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
}

/// Deducted type information for expressions on the sides of a relational operator
enum OpTypeInfo {
    none,
    /// Both sides are floating points
    floatingPoint,
    /// Either side is a pointer
    pointer,
    /// Both sides are bools
    boolean,
    /// lhs and rhs sides are the same enum decl
    enumLhsRhsIsSame,
    /// lhs is the minimal representation in the enum type
    enumLhsIsMin,
    /// lhs is the maximum representation in the enum type
    enumLhsIsMax,
    /// rhs is the minimum representation in the enum type
    enumRhsIsMin,
    /// rhs is the maximum representation in the enum type
    enumRhsIsMax,
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

    size_t toHash() @safe nothrow const scope {
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
