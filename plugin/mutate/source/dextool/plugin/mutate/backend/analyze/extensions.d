/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Extensions to the visitor in `cpptooling.analyzer.clang.ast`.

Intende to move this code to clang_extensions if this approach to extending the
clang AST works well.
*/
module dextool.plugin.mutate.backend.analyze.extensions;

import clang.Cursor : Cursor;
import cpptooling.analyzer.clang.ast : Visitor;

import dextool.set;

static import dextool.clang_extensions;

static import cpptooling.analyzer.clang.ast;

/**
 * the ignoreCursors solution is not particularly principaled. It is an ugly hack that should be moved to the core AST `Visitor` and thus completely h
 */
class ExtendedVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import dextool.clang_extensions;

    alias visit = Visitor.visit;

    // A cursors that has been decorated as one of the extended should be
    // "ignored" if it is found "again". Which happens for e.g. a
    // BinaryOperator inside a if-statement. It will first occur as a
    // IfStmtCond and then a BinaryOperator.
    Set!size_t ignoreCursors;

    void visit(const(IfStmtInit) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(IfStmtCond) value) {
        visit(cast(const(Expression)) value);
    }

    void visit(const(IfStmtThen) value) {
        visit(cast(const(Statement)) value);
    }

    void visit(const(IfStmtElse) value) {
        visit(cast(const(Statement)) value);
    }
}

// using dispatch because the wrapped cursor has to be re-visited as its
// original `type`. Not just the colored `IfStmt` node.

final class IfStmtInit : cpptooling.analyzer.clang.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.dispatch(cursor, v);
    }
}

final class IfStmtCond : cpptooling.analyzer.clang.ast.Expression {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.dispatch(cursor, v);
    }
}

final class IfStmtThen : cpptooling.analyzer.clang.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.dispatch(cursor, v);
    }
}

final class IfStmtElse : cpptooling.analyzer.clang.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.dispatch(cursor, v);
    }
}

void accept(T)(const(cpptooling.analyzer.clang.ast.IfStmt) n, T v)
        if (is(T : ExtendedVisitor)) {
    import dextool.clang_extensions;

    auto stmt = getIfStmt(n.cursor);
    accept(stmt, v);
}

void accept(T)(ref dextool.clang_extensions.IfStmt n, T v)
        if (is(T : ExtendedVisitor)) {
    import std.traits : hasMember;

    static if (hasMember!(T, "incr"))
        v.incr;

    if (n.init_.isValid) {
        auto sub = new IfStmtInit(n.init_);
        static if (__traits(hasMember, T, "ignoreCursors")) {
            v.ignoreCursors.add(n.init_.toHash);
        }
        v.visit(sub);
    }
    if (n.cond.isValid) {
        auto sub = new IfStmtCond(n.cond);
        static if (__traits(hasMember, T, "ignoreCursors")) {
            v.ignoreCursors.add(n.cond.toHash);
        }
        v.visit(sub);
    }
    if (n.then.isValid) {
        auto sub = new IfStmtThen(n.then);
        v.visit(sub);
    }
    if (n.else_.isValid) {
        auto sub = new IfStmtElse(n.else_);
        v.visit(sub);
    }

    static if (hasMember!(T, "decr"))
        v.decr;
}
