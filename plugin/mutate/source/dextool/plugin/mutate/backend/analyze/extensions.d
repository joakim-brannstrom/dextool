/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Extensions to the visitor in `libclang_ast.ast`.

Intende to move this code to clang_extensions if this approach to extending the
clang AST works well.
*/
module dextool.plugin.mutate.backend.analyze.extensions;

import clang.Cursor : Cursor;
import libclang_ast.ast : Visitor;

import my.set;

static import dextool.clang_extensions;

static import libclang_ast.ast;

/**
 * the ignoreCursors solution is not particularly principaled. It is an ugly hack that should be moved to the core AST `Visitor` and thus completely h
 */
class ExtendedVisitor : Visitor {
    import libclang_ast.ast;
    import dextool.clang_extensions;

    alias visit = Visitor.visit;

    // A cursors that has been decorated as one of the extended should be
    // "ignored" if it is found "again". Which happens for e.g. a
    // BinaryOperator inside a if-statement. It will first occur as a
    // IfStmtCond and then a BinaryOperator.
    Set!size_t ignoreCursors;

    void visit(scope const IfStmtInit value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const IfStmtCond value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const IfStmtCondVar value) {
        visit(cast(const(Expression)) value);
    }

    void visit(scope const IfStmtThen value) {
        visit(cast(const(Statement)) value);
    }

    void visit(scope const IfStmtElse value) {
        visit(cast(const(Statement)) value);
    }
}

// using dispatch because the wrapped cursor has to be re-visited as its
// original `type`. Not just the colored `IfStmt` node.

final class IfStmtInit : libclang_ast.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.dispatch(cursor, v);
    }
}

final class IfStmtCond : libclang_ast.ast.Expression {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.dispatch(cursor, v);
    }
}

final class IfStmtCondVar : libclang_ast.ast.Expression {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.dispatch(cursor, v);
    }
}

final class IfStmtThen : libclang_ast.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.dispatch(cursor, v);
    }
}

final class IfStmtElse : libclang_ast.ast.Statement {
    this(Cursor cursor) @safe {
        super(cursor);
    }

    void accept(ExtendedVisitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.dispatch(cursor, v);
    }
}

void accept(T)(scope const libclang_ast.ast.IfStmt n, T v)
        if (is(T : ExtendedVisitor)) {
    import dextool.clang_extensions;

    auto stmt = getIfStmt(n.cursor);
    accept(stmt, v);
}

void accept(T)(scope dextool.clang_extensions.IfStmt n, T v)
        if (is(T : ExtendedVisitor)) {
    import std.traits : hasMember;

    void incr() {
        static if (hasMember!(T, "incr"))
            v.incr;
    }

    void decr() {
        static if (hasMember!(T, "decr"))
            v.decr;
    }

    void ignore(Cursor c) {
        static if (__traits(hasMember, T, "ignoreCursors"))
            v.ignoreCursors.add(c.toHash);
    }

    static if (__traits(hasMember, T, "ignoreCursors")) {
        {
            const h = n.cursor.toHash;
            if (h in v.ignoreCursors) {
                v.ignoreCursors.remove(h);
                return;
            }
            v.ignoreCursors.add(h);
        }
    }

    incr();
    scope (exit)
        decr();

    if (n.init_.isValid) {
        ignore(n.init_);
        scope sub = new IfStmtInit(n.init_);
        v.visit(sub);
    }
    if (n.cond.isValid) {
        if (n.conditionVariable.isValid) {
            incr();

            ignore(n.conditionVariable);
            scope sub = new IfStmtCondVar(n.conditionVariable);
            v.visit(sub);
        }

        ignore(n.cond);
        scope sub = new IfStmtCond(n.cond);
        v.visit(sub);

        if (n.conditionVariable.isValid)
            decr();
    }
    if (n.then.isValid) {
        scope sub = new IfStmtThen(n.then);
        v.visit(sub);
    }
    if (n.else_.isValid) {
        scope sub = new IfStmtElse(n.else_);
        v.visit(sub);
    }
}
