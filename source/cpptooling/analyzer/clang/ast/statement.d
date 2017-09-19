/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

DO NOT EDIT. THIS FILE IS GENERATED.
See the generator script source/devtool/generator_clang_ast_nodes.d
*/
module cpptooling.analyzer.clang.ast.statement;
import cpptooling.analyzer.clang.ast.node : Node;

abstract class Statement : Node {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.ast : Visitor;

    Cursor cursor;
    alias cursor this;

    this(Cursor cursor) @safe {
        this.cursor = cursor;
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}


final class UnexposedStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class LabelStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CompoundStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CaseStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class DefaultStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class IfStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class SwitchStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class WhileStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class DoStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ForStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class GotoStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class IndirectGotoStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ContinueStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class BreakStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ReturnStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class AsmStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCAtTryStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCAtCatchStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCAtFinallyStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCAtThrowStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCAtSynchronizedStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCAutoreleasePoolStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCForCollectionStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxCatchStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxTryStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxForRangeStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class SehTryStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class SehExceptStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class SehFinallyStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class MsAsmStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class NullStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class DeclStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class SehLeaveStmt : Statement {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

