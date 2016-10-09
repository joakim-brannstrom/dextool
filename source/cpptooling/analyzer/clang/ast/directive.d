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
module cpptooling.analyzer.clang.ast.directive;
import cpptooling.analyzer.clang.ast.node : Node;

abstract class Directive : Node {
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

final class OMPParallelDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPSimdDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPForDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPSectionsDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPSectionDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPSingleDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPParallelForDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPParallelSectionsDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPTaskDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPMasterDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPCriticalDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPTaskyieldDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPBarrierDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPTaskwaitDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPFlushDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class SEHLeaveStmt : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPOrderedDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPAtomicDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPForSimdDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPParallelForSimdDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPTargetDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPTeamsDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPTaskgroupDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPCancellationPointDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class OMPCancelDirective : Directive {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;

        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}
