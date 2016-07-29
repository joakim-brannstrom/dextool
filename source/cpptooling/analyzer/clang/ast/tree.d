/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.tree;

import logger = std.experimental.logger;

import clang.Cursor : Cursor;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.attribute;
import cpptooling.analyzer.clang.ast.declaration;
import cpptooling.analyzer.clang.ast.directive;
import cpptooling.analyzer.clang.ast.expression;
import cpptooling.analyzer.clang.ast.preprocessor;
import cpptooling.analyzer.clang.ast.reference;
import cpptooling.analyzer.clang.ast.statement;
import cpptooling.analyzer.clang.ast.translationunit;

import cpptooling.analyzer.clang.ast.visitor : CXCursorKind_PrefixLen;

version (unittest) {
    import unit_threaded : Name, shouldEqual, shouldBeTrue;
} else {
    private struct Name {
        string name_;
    }
}

private enum hasIncrDecr(VisitorT) = __traits(hasMember, VisitorT, "incr")
        && __traits(hasMember, VisitorT, "decr");

/**
 * Wrap a clang cursor. No restrictions on what type of cursor it is.
 * Accept a Visitor.
 * During accept traverse the AST to:
 *  - wrap Cursors's in specific classes corresponding to the kind of cursor.
 *  - call Visitor's visit(...) with wrapped cursor.
 *
 * Starts traversing the AST from the root.
 *
 * Optional functions:
 *   void incr(). Called before descending a node.
 *   void decr(). Called after ascending a node.
 */
struct ClangAST(VisitorT) {
    import std.traits : isArray;
    import clang.Cursor : Cursor;

    @disable this();

    private Cursor root;

    this(Cursor cursor) {
        this.root = cursor;
    }

    void accept(ref VisitorT visitor) @safe {
        static if (isArray!VisitorT && hasIncrDecr!(typeof(VisitorT.init[0]))) {
            foreach (v; visitor) {
                v.incr();
            }

            scope (success) {
                foreach (v; visitor) {
                    v.decr();
                }
            }

        } else if (hasIncrDecr!VisitorT) {
            visitor.incr();
            scope (success)
                visitor.decr();
        }

        dispatch(root, visitor);
    }
}

void accept(VisitorT)(ref const(Cursor) cursor, ref VisitorT visitor) @safe {
    import std.traits : isArray;
    import clang.Visitor : Visitor;

    static if (isArray!VisitorT && hasIncrDecr!(typeof(VisitorT.init[0]))) {
        foreach (v; visitor) {
            v.incr();
        }

        scope (success) {
            foreach (v; visitor) {
                v.decr();
            }
        }

    } else if (hasIncrDecr!VisitorT) {
        visitor.incr();
        scope (success)
            visitor.decr();
    }

    () @trusted{
        foreach (child, _; Visitor(cursor)) {
            dispatch(child, visitor);
        }
    }();
}

void dispatch(VisitorT)(ref const(Cursor) cursor, ref VisitorT visitor) @safe {
    import std.conv : to;

    switch (cursor.kind) {
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, AttributeSeq));
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, DeclarationSeq));
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, DirectiveSeq));
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, ExpressionSeq));
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, PreprocessorSeq));
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, ReferenceSeq));
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, StatementSeq));
        mixin(wrapCursor!(CXCursorKind_PrefixLen, visitor, cursor, TranslationUnitSeq));

    default:
        logger.error("Node not handled:", to!string(cursor.kind));
    }
}

private:

template wrapCursor(ulong skipBeginLen, alias visitor, alias cursor, cases...) {
    static if (cases.length > 1) {
        enum wrapCursor = wrapCursor!(skipBeginLen, visitor, cursor, cases[0]) ~ wrapCursor!(skipBeginLen,
                    visitor, cursor, cases[1 .. $]);
    } else {
        import std.format : format;

        static if (is(typeof(visitor) : T[], T)) {
            // is an array
            enum visit = "foreach (v; " ~ visitor.stringof ~ ") { v.visit(wrapped); }";
        } else {
            enum visit = visitor.stringof ~ ".visit(wrapped);";
        }

        enum parent = __traits(parent, cases[0]).stringof;
        enum case0_skip = cases[0].stringof[skipBeginLen .. $];
        //TODO allocate in an allocator, not GC with "new"
        enum wrapCursor = format("case %s.%s: auto wrapped = new %s(%s); %s break;\n",
                    parent, cases[0].stringof, case0_skip, cursor.stringof, visit);
    }
}

@Name("Should be a bounch of 'case'")
unittest {
    import std.conv : to;

    enum Dummy {
        xCase1,
        xCase2
    }

    int visitor;
    int cursor;

    wrapCursor!(1, visitor, cursor, Dummy.xCase1, Dummy.xCase2).shouldEqual(
            "case Dummy.xCase1: auto wrapped = new Case1(cursor); visitor.visit(wrapped); break;
case Dummy.xCase2: auto wrapped = new Case2(cursor); visitor.visit(wrapped); break;
");
}

@Name("A name for the test")
@safe unittest {
    import cpptooling.analyzer.clang.ast.visitor : Visitor;

    final class TestVisitor : Visitor {
        alias visit = Visitor.visit;

        bool attribute;
        override void visit(const(Attribute)) {
            attribute = true;
        }

        bool declaration;
        override void visit(const(Declaration)) {
            declaration = true;
        }

        bool directive;
        override void visit(const(Directive)) {
            directive = true;
        }

        bool expression;
        override void visit(const(Expression)) {
            expression = true;
        }

        bool preprocessor;
        override void visit(const(Preprocessor)) {
            preprocessor = true;
        }

        bool reference;
        override void visit(const(Reference)) {
            reference = true;
        }

        bool statement;
        override void visit(const(Statement)) {
            statement = true;
        }

        bool translationunit;
        override void visit(const(TranslationUnit)) {
            translationunit = true;
        }
    }

    auto test = new TestVisitor;

    Cursor cursor;

    foreach (kind; [AttributeSeq[0], DeclarationSeq[0], DirectiveSeq[0],
            ExpressionSeq[0], PreprocessorSeq[0], ReferenceSeq[0],
            StatementSeq[0], TranslationUnitSeq[0]]) {
        switch (kind) {
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, AttributeSeq));
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, DeclarationSeq));
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, DirectiveSeq));
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, ExpressionSeq));
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, PreprocessorSeq));
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, ReferenceSeq));
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, StatementSeq));
            mixin(wrapCursor!(CXCursorKind_PrefixLen, test, cursor, TranslationUnitSeq));
        default:
            assert(0);
        }
    }

    test.attribute.shouldBeTrue;
    test.declaration.shouldBeTrue;
    test.directive.shouldBeTrue;
    test.expression.shouldBeTrue;
    test.preprocessor.shouldBeTrue;
    test.reference.shouldBeTrue;
    test.statement.shouldBeTrue;
    test.translationunit.shouldBeTrue;
}
