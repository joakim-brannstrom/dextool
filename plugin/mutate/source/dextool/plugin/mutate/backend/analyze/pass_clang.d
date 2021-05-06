/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.pass_clang;

import logger = std.experimental.logger;
import std.algorithm : among, map, sort, filter;
import std.array : empty, array, appender, Appender;
import std.exception : collectException;
import std.format : formattedWrite;
import std.meta : AliasSeq;
import std.typecons : Nullable;

import blob_model : Blob;
import my.container.vector : vector, Vector;
import my.gc.refc : RefCounted;
import my.optional;

import clang.Cursor : Cursor;
import clang.Eval : Eval;
import clang.Type : Type;
import clang.c.Index : CXTypeKind, CXCursorKind, CXEvalResultKind, CXTokenKind;

import libclang_ast.ast : Visitor;
import libclang_ast.cursor_logger : logNode, mixinNodeLog;

import dextool.clang_extensions : getUnderlyingExprNode;

import dextool.type : Path, AbsolutePath;

import dextool.plugin.mutate.backend.analyze.ast : Interval, Location, TypeKind,
    Node, Ast, BreathFirstRange;
import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, InvalidPathException;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset, SourceLocRange;

import analyze = dextool.plugin.mutate.backend.analyze.ast;

alias accept = dextool.plugin.mutate.backend.analyze.extensions.accept;

/** Translate a clang AST to a mutation AST.
 */
ClangResult toMutateAst(const Cursor root, FilesysIO fio) @safe {
    import libclang_ast.ast;

    auto visitor = new BaseVisitor(fio);
    scope (exit)
        visitor.dispose;
    auto ast = ClangAST!BaseVisitor(root);
    ast.accept(visitor);
    visitor.ast.releaseCache;

    auto rval = ClangResult(visitor.ast, visitor.includes.data);
    return rval;
}

struct ClangResult {
    RefCounted!(analyze.Ast) ast;

    /// All dependencies that the root has.
    Path[] dependencies;
}

private:

struct OperatorCursor {
    analyze.Expr astOp;

    // true if the operator is overloaded.
    bool isOverload;

    // the whole expression
    analyze.Location exprLoc;
    DeriveCursorTypeResult exprTy;

    // the operator itself
    analyze.Operator operator;
    analyze.Location opLoc;

    Cursor lhs;
    Cursor rhs;

    /// Add the result to the AST and astOp to the parent.
    /// astOp is set to have two children, lhs and rhs.
    void put(analyze.Node parent, ref analyze.Ast ast) @safe {
        ast.put(astOp, exprLoc);
        ast.put(operator, opLoc);

        exprTy.put(ast);

        if (exprTy.type !is null)
            ast.put(astOp, exprTy.id);

        if (exprTy.symbol !is null)
            ast.put(astOp, exprTy.symId);

        parent.children ~= astOp;
    }
}

Nullable!OperatorCursor operatorCursor(T)(ref Ast ast, T node) {
    import dextool.clang_extensions : getExprOperator, OpKind, ValueKind, getUnderlyingExprNode;

    auto op = getExprOperator(node.cursor);
    if (!op.isValid)
        return typeof(return)();

    auto path = op.cursor.location.path.Path;
    if (path.empty)
        return typeof(return)();

    OperatorCursor res;

    void sidesPoint() {
        auto sides = op.sides;
        if (sides.lhs.isValid) {
            res.lhs = getUnderlyingExprNode(sides.lhs);
        }
        if (sides.rhs.isValid) {
            res.rhs = getUnderlyingExprNode(sides.rhs);
        }
    }

    // the operator itself
    void opPoint() {
        auto loc = op.location;
        auto sr = loc.spelling;
        res.operator = ast.make!(analyze.Operator);
        res.opLoc = analyze.Location(path, Interval(sr.offset,
                cast(uint)(sr.offset + op.length)), SourceLocRange(SourceLoc(loc.line,
                loc.column), SourceLoc(loc.line, cast(uint)(loc.column + op.length))));
    }

    // the arguments and the operator
    void exprPoint() {
        auto sr = op.cursor.extent;
        res.exprLoc = analyze.Location(path, Interval(sr.start.offset,
                sr.end.offset), SourceLocRange(SourceLoc(sr.start.line,
                sr.start.column), SourceLoc(sr.end.line, sr.end.column)));
        res.exprTy = deriveCursorType(ast, op.cursor);
        switch (op.kind) with (OpKind) {
        case OO_Star: // "*"
            res.isOverload = true;
            goto case;
        case Mul: // "*"
            res.astOp = ast.make!(analyze.OpMul);
            break;
        case OO_Slash: // "/"
            res.isOverload = true;
            goto case;
        case Div: // "/"
            res.astOp = ast.make!(analyze.OpDiv);
            break;
        case OO_Percent: // "%"
            res.isOverload = true;
            goto case;
        case Rem: // "%"
            res.astOp = ast.make!(analyze.OpMod);
            break;
        case OO_Plus: // "+"
            res.isOverload = true;
            goto case;
        case Add: // "+"
            res.astOp = ast.make!(analyze.OpAdd);
            break;
        case OO_Minus: // "-"
            res.isOverload = true;
            goto case;
        case Sub: // "-"
            res.astOp = ast.make!(analyze.OpSub);
            break;
        case OO_Less: // "<"
            res.isOverload = true;
            goto case;
        case LT: // "<"
            res.astOp = ast.make!(analyze.OpLess);
            break;
        case OO_Greater: // ">"
            res.isOverload = true;
            goto case;
        case GT: // ">"
            res.astOp = ast.make!(analyze.OpGreater);
            break;
        case OO_LessEqual: // "<="
            res.isOverload = true;
            goto case;
        case LE: // "<="
            res.astOp = ast.make!(analyze.OpLessEq);
            break;
        case OO_GreaterEqual: // ">="
            res.isOverload = true;
            goto case;
        case GE: // ">="
            res.astOp = ast.make!(analyze.OpGreaterEq);
            break;
        case OO_EqualEqual: // "=="
            res.isOverload = true;
            goto case;
        case EQ: // "=="
            res.astOp = ast.make!(analyze.OpEqual);
            break;
        case OO_Exclaim: // "!"
            res.isOverload = true;
            goto case;
        case LNot: // "!"
            res.astOp = ast.make!(analyze.OpNegate);
            break;
        case OO_ExclaimEqual: // "!="
            res.isOverload = true;
            goto case;
        case NE: // "!="
            res.astOp = ast.make!(analyze.OpNotEqual);
            break;
        case OO_AmpAmp: // "&&"
            res.isOverload = true;
            goto case;
        case LAnd: // "&&"
            res.astOp = ast.make!(analyze.OpAnd);
            break;
        case OO_PipePipe: // "||"
            res.isOverload = true;
            goto case;
        case LOr: // "||"
            res.astOp = ast.make!(analyze.OpOr);
            break;
        case OO_Amp: // "&"
            res.isOverload = true;
            goto case;
        case And: // "&"
            res.astOp = ast.make!(analyze.OpAndBitwise);
            break;
        case OO_Pipe: // "|"
            res.isOverload = true;
            goto case;
        case Or: // "|"
            res.astOp = ast.make!(analyze.OpOrBitwise);
            break;
        case OO_StarEqual: // "*="
            res.isOverload = true;
            goto case;
        case MulAssign: // "*="
            res.astOp = ast.make!(analyze.OpAssignMul);
            break;
        case OO_SlashEqual: // "/="
            res.isOverload = true;
            goto case;
        case DivAssign: // "/="
            res.astOp = ast.make!(analyze.OpAssignDiv);
            break;
        case OO_PercentEqual: // "%="
            res.isOverload = true;
            goto case;
        case RemAssign: // "%="
            res.astOp = ast.make!(analyze.OpAssignMod);
            break;
        case OO_PlusEqual: // "+="
            res.isOverload = true;
            goto case;
        case AddAssign: // "+="
            res.astOp = ast.make!(analyze.OpAssignAdd);
            break;
        case OO_MinusEqual: // "-="
            res.isOverload = true;
            goto case;
        case SubAssign: // "-="
            res.astOp = ast.make!(analyze.OpAssignSub);
            break;
        case OO_AmpEqual: // "&="
            res.isOverload = true;
            goto case;
        case AndAssign: // "&="
            res.astOp = ast.make!(analyze.OpAssignAndBitwise);
            break;
        case OO_PipeEqual: // "|="
            res.isOverload = true;
            goto case;
        case OrAssign: // "|="
            res.astOp = ast.make!(analyze.OpAssignOrBitwise);
            break;
        case OO_CaretEqual: // "^="
            res.isOverload = true;
            goto case;
        case OO_Equal: // "="
            goto case;
        case ShlAssign: // "<<="
            goto case;
        case ShrAssign: // ">>="
            goto case;
        case XorAssign: // "^="
            goto case;
        case Assign: // "="
            res.astOp = ast.make!(analyze.OpAssign);
            break;
            //case Xor: // "^"
            //case OO_Caret: // "^"
            //case OO_Tilde: // "~"
        default:
            res.astOp = ast.make!(analyze.BinaryOp);
        }
    }

    exprPoint;
    opPoint;
    sidesPoint;
    return typeof(return)(res);
}

@safe:

Location toLocation(ref const Cursor c) {
    auto e = c.extent;
    auto interval = Interval(e.start.offset, e.end.offset);
    auto begin = e.start;
    auto end = e.end;
    return Location(e.path.Path, interval, SourceLocRange(SourceLoc(begin.line,
            begin.column), SourceLoc(end.line, end.column)));
}

/** Find all mutation points that affect a whole expression.
 *
 * TODO change the name of the class. It is more than just an expression
 * visitor.
 *
 * # Usage of kind_stack
 * All usage of the kind_stack shall be documented here.
 *  - track assignments to avoid generating unary insert operators for the LHS.
 */
final class BaseVisitor : ExtendedVisitor {
    import clang.c.Index : CXCursorKind, CXTypeKind;
    import libclang_ast.ast;
    import dextool.clang_extensions : getExprOperator, OpKind;
    import my.set;

    alias visit = ExtendedVisitor.visit;

    // the depth the visitor is at.
    uint indent;
    // A stack of the nodes that are generated up to the current one.
    Stack!(analyze.Node) nstack;

    // A stack of visited cursors up to the current one.
    Stack!(CXCursorKind) cstack;

    /// The elements that where removed from the last decrement.
    Vector!(analyze.Node) lastDecr;

    /// List of macro locations which blacklist mutants that would be injected
    /// in any of them.
    BlackList blacklist;

    RefCounted!(analyze.Ast) ast;
    Appender!(Path[]) includes;

    /// Keep track of visited nodes to avoid circulare references.
    Set!size_t isVisited;

    FilesysIO fio;

    this(FilesysIO fio) nothrow {
        this.fio = fio;
        this.ast = analyze.Ast.init;
    }

    void dispose() {
        ast.release;
    }

    /// Returns: the depth (1+) if any of the parent nodes is `k`.
    uint isParent(K...)(auto ref K k) {
        return cstack.isParent(k);
    }

    /// Returns: if the previous nodes is a CXCursorKind `k`.
    bool isDirectParent(CXCursorKind k) {
        if (cstack.empty)
            return false;
        return cstack[$ - 1].data == k;
    }

    override void incr() @safe {
        ++indent;
        lastDecr.clear;
    }

    override void decr() @trusted {
        --indent;
        lastDecr = nstack.popUntil(indent);
        cstack.popUntil(indent);
    }

    private void pushStack(analyze.Node n, analyze.Location l, const CXCursorKind cKind) @trusted {
        n.blacklist = n.blacklist || blacklist.inside(l);
        n.schemaBlacklist = n.blacklist || n.schemaBlacklist;
        if (!nstack.empty)
            n.schemaBlacklist = n.schemaBlacklist || nstack[$ - 1].data.schemaBlacklist;
        nstack.put(n, indent);
        cstack.put(cKind, indent);
        ast.put(n, l);
    }

    /// Returns: true if it is OK to modify the cursor
    private void pushStack(AstT, ClangT)(AstT n, ClangT c) @trusted {
        static if (is(ClangT == Cursor))
            auto loc = c.toLocation;
        else
            auto loc = c.cursor.toLocation;
        nstack.back.children ~= n;
        pushStack(n, loc, c.kind);
    }

    override void visit(const TranslationUnit v) {
        import clang.c.Index : CXLanguageKind;

        mixin(mixinNodeLog!());

        ast.root = ast.make!(analyze.TranslationUnit);
        auto loc = v.cursor.toLocation;
        pushStack(ast.root, loc, v.cursor.kind);

        blacklist = BlackList(v.cursor);

        // it is most often invalid
        switch (v.cursor.language) {
        case CXLanguageKind.c:
            ast.lang = Language.c;
            break;
        case CXLanguageKind.cPlusPlus:
            ast.lang = Language.cpp;
            break;
        default:
            ast.lang = Language.assumeCpp;
        }

        v.accept(this);
    }

    override void visit(const Attribute v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const Declaration v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const VarDecl v) @trusted {
        mixin(mixinNodeLog!());
        visitVar(v);
        v.accept(this);
    }

    override void visit(const ParmDecl v) @trusted {
        mixin(mixinNodeLog!());
        visitVar(v);
        v.accept(this);
    }

    override void visit(const ClassTemplate v) {
        mixin(mixinNodeLog!());
        // by adding the node it is possible to search for it in cstack
        auto n = ast.make!(analyze.Poision);
        pushStack(n, v);
        v.accept(this);
    }

    override void visit(const ClassTemplatePartialSpecialization v) {
        mixin(mixinNodeLog!());
        // by adding the node it is possible to search for it in cstack
        auto n = ast.make!(analyze.Poision);
        pushStack(n, v);
        v.accept(this);
    }

    override void visit(const FunctionTemplate v) {
        mixin(mixinNodeLog!());
        auto n = ast.make!(analyze.Function);
        // it is too uncertain to inject mutant schematan inside a template
        // because the types are not known which lead to a high probability
        // that the schemata code will fail to compile.
        n.schemaBlacklist = true;
        pushStack(n, v);

        v.accept(this);
    }

    override void visit(const TemplateTypeParameter v) {
        mixin(mixinNodeLog!());
        // block mutants inside template parameters
    }

    override void visit(const TemplateTemplateParameter v) {
        mixin(mixinNodeLog!());
        // block mutants inside template parameters
    }

    override void visit(const NonTypeTemplateParameter v) {
        mixin(mixinNodeLog!());
        // block mutants inside template parameters
    }

    override void visit(const TypeAliasDecl v) {
        mixin(mixinNodeLog!());
        // block mutants inside template parameters
    }

    override void visit(const CxxBaseSpecifier v) {
        mixin(mixinNodeLog!());
        // block mutants inside template parameters.
        // the only mutants that are inside an inheritance is template
        // parameters and such.
    }

    private void visitVar(T)(T v) @trusted {
        //auto bar = ast.make!(analyze.VarDecl);
        //bar.isConst = true;
        //logger.tracef("%x", cast(void*) bar);

        auto n = ast.make!(analyze.VarDecl);

        auto ty = v.cursor.type;
        if (ty.isValid) {
            n.isConst = ty.isConst;

            // block schematas if the visitor is inside a const declared
            // variable. a schemata is dependent on a runtime variable but a
            // const declaration requires its expression to be resolved at
            // compile time. Thus if a schema mutant is injected inside this
            // part of the tree it will result in a schema that do not compile.
            n.schemaBlacklist = ty.isConst;
        }

        pushStack(n, v);
    }

    override void visit(const Directive v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const InclusionDirective v) @trusted {
        import std.file : exists;
        import std.path : buildPath, dirName;

        mixin(mixinNodeLog!());

        const spell = v.spelling;
        const file = v.cursor.location.file.name;
        const p = buildPath(file.dirName, spell);
        if (exists(p))
            includes.put(Path(p));
        else
            includes.put(Path(spell));

        v.accept(this);
    }

    override void visit(const Reference v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    // TODO overlapping logic with Expression. deduplicate
    override void visit(const DeclRefExpr v) @trusted {
        import libclang_ast.ast : dispatch;
        import clang.SourceRange : intersects;

        mixin(mixinNodeLog!());

        if (v.cursor.toHash in isVisited)
            return;
        isVisited.add(v.cursor.toHash);

        auto n = ast.make!(analyze.Expr);
        n.schemaBlacklist = isParent(CXCursorKind.classTemplate,
                CXCursorKind.classTemplatePartialSpecialization, CXCursorKind.functionTemplate) != 0;

        auto ue = deriveCursorType(ast, v.cursor);
        ue.put(ast);
        if (ue.type !is null) {
            ast.put(n, ue.id);
        }

        // only deref a node which is a self-reference
        auto r = v.cursor.referenced;
        if (r.isValid && r != v.cursor && intersects(v.cursor.extent, r.extent)
                && r.toHash !in isVisited) {
            isVisited.add(r.toHash);
            pushStack(n, v);

            incr;
            scope (exit)
                decr;
            dispatch(r, this);
        } else if (ue.expr.isValid && ue.expr != v.cursor && ue.expr.toHash !in isVisited) {
            isVisited.add(ue.expr.toHash);
            pushStack(n, ue.expr);

            incr;
            scope (exit)
                decr;
            dispatch(ue.expr, this);
        } else {
            pushStack(n, v);
            v.accept(this);
        }
    }

    override void visit(const Statement v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const ArraySubscriptExpr v) {
        mixin(mixinNodeLog!());
        // block schematan inside subscripts because some lead to compilation
        // errors. Need to investigate more to understand why and how to avoid.
        // For now they are blocked.
        auto n = ast.make!(analyze.Poision);
        n.schemaBlacklist = true;
        pushStack(n, v);
        v.accept(this);
    }

    override void visit(const Expression v) {
        mixin(mixinNodeLog!());

        if (v.cursor.toHash in isVisited)
            return;
        isVisited.add(v.cursor.toHash);

        auto n = ast.make!(analyze.Expr);
        n.schemaBlacklist = isParent(CXCursorKind.classTemplate,
                CXCursorKind.classTemplatePartialSpecialization, CXCursorKind.functionTemplate) != 0;

        auto ue = deriveCursorType(ast, v.cursor);
        ue.put(ast);
        if (ue.type !is null) {
            ast.put(n, ue.id);
        }

        pushStack(n, v);
        v.accept(this);
    }

    override void visit(const Preprocessor v) {
        mixin(mixinNodeLog!());

        const bool isCpp = v.spelling == "__cplusplus";

        if (isCpp)
            ast.lang = Language.cpp;
        else if (!isCpp && ast.lang != Language.cpp)
            ast.lang = Language.c;

        v.accept(this);
    }

    override void visit(const EnumDecl v) @trusted {
        mixin(mixinNodeLog!());

        // extract the boundaries of the enum to update the type db.
        scope vis = new EnumVisitor(ast.get, indent);
        vis.visit(v);
        ast.types.set(vis.id, vis.toType);
    }

    override void visit(const FunctionDecl v) @trusted {
        mixin(mixinNodeLog!());
        visitFunc(v);
    }

    override void visit(const Constructor v) @trusted {
        mixin(mixinNodeLog!());

        auto n = ast.make!(analyze.Poision);
        n.schemaBlacklist = isConstExpr(v.cursor);
        pushStack(n, v);

        // skip all "= default"
        if (!v.cursor.isDefaulted)
            v.accept(this);
    }

    override void visit(const Destructor v) @trusted {
        mixin(mixinNodeLog!());

        auto n = ast.make!(analyze.Poision);
        n.schemaBlacklist = isConstExpr(v.cursor);
        pushStack(n, v);

        // skip all "= default"
        if (!v.cursor.isDefaulted)
            v.accept(this);
        // TODO: no test covers this case where = default is used for a
        // destructor. For some versions of clang a CompoundStmt is generated
    }

    override void visit(const CxxMethod v) {
        mixin(mixinNodeLog!());

        // model C++ methods as functions. It should be enough to know that it
        // is a function and the return type when generating mutants.

        // skip all "= default"
        if (!v.cursor.isDefaulted)
            visitFunc(v);
    }

    override void visit(const BreakStmt v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const BinaryOperator v) @trusted {
        mixin(mixinNodeLog!());

        visitOp(v, v.cursor.kind);
    }

    override void visit(const UnaryOperator v) @trusted {
        mixin(mixinNodeLog!());
        visitOp(v, v.cursor.kind);
    }

    override void visit(const CompoundAssignOperator v) {
        mixin(mixinNodeLog!());
        // TODO: implement all aor assignment such as +=
        pushStack(ast.make!(analyze.OpAssign), v);
        v.accept(this);
    }

    override void visit(const CallExpr v) {
        mixin(mixinNodeLog!());

        if (!visitOp(v, v.cursor.kind)) {
            visitCall(v);
        }
    }

    override void visit(const CxxThrowExpr v) {
        mixin(mixinNodeLog!());
        // model a C++ exception as a return expression because that is
        // "basically" what happens.
        auto n = ast.make!(analyze.Return);
        n.blacklist = true;
        pushStack(n, v);
        v.accept(this);
    }

    override void visit(const InitListExpr v) {
        mixin(mixinNodeLog!());
        pushStack(ast.make!(analyze.Constructor), v);
        v.accept(this);
    }

    override void visit(const LambdaExpr v) {
        mixin(mixinNodeLog!());

        // model C++ lambdas as functions. It should be enough to know that it
        // is a function and the return type when generating mutants.
        visitFunc(v);
    }

    override void visit(const ReturnStmt v) {
        mixin(mixinNodeLog!());
        pushStack(ast.make!(analyze.Return), v);
        v.accept(this);
    }

    override void visit(const CompoundStmt v) {
        import std.algorithm : min;

        mixin(mixinNodeLog!());

        static uint findBraketOffset(Blob file, const uint begin, const uint end, const ubyte letter) {
            for (uint i = begin; i < end; ++i) {
                if (file.content[i] == letter) {
                    return i;
                }
            }
            return begin;
        }

        if (isDirectParent(CXCursorKind.switchStmt)) {
            // the CompoundStmt statement {} directly inside a switch statement
            // isn't useful to manipulate as a block. The useful part is the
            // smaller blocks that the case and default break down the block
            // into thus this avoid generating useless blocks that lead to
            // equivalent or unproductive mutants.
        } else
            try {
                auto loc = v.cursor.toLocation;
                auto file = fio.makeInput(loc.file);
                const maxEnd = file.content.length;

                // The block that can be modified is the inside of it thus the
                // a CompoundStmt that represent a "{..}" can for example be the
                // body of a function or the block that a try statement encompase.
                // done then a SDL can't be generated that delete the inside of
                // e.g. void functions.

                auto end = min(findBraketOffset(file, loc.interval.end == 0
                        ? loc.interval.end : loc.interval.end - 1, cast(uint) maxEnd,
                        cast(ubyte) '}'), maxEnd);
                auto begin = findBraketOffset(file, loc.interval.begin, end, cast(ubyte) '{');

                if (begin < end)
                    begin = begin + 1;

                // TODO: need to adjust sloc too
                loc.interval = Interval(begin, end);

                auto n = ast.make!(analyze.Block);
                nstack.back.children ~= n;
                pushStack(n, loc, v.cursor.kind);
            } catch (InvalidPathException e) {
            } catch (Exception e) {
                logger.trace(e.msg).collectException;
            }

        v.accept(this);
    }

    override void visit(const CaseStmt v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const DefaultStmt v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const ForStmt v) {
        mixin(mixinNodeLog!());
        pushStack(ast.make!(analyze.Loop), v);

        auto visitor = new FindVisitor!CompoundStmt;
        v.accept(visitor);

        if (visitor.node !is null) {
            this.visit(visitor.node);
        }
    }

    override void visit(const CxxForRangeStmt v) {
        mixin(mixinNodeLog!());
        pushStack(ast.make!(analyze.Loop), v);

        auto visitor = new FindVisitor!CompoundStmt;
        v.accept(visitor);

        if (visitor.node !is null) {
            this.visit(visitor.node);
        }
    }

    override void visit(const WhileStmt v) {
        mixin(mixinNodeLog!());
        pushStack(ast.make!(analyze.Loop), v);
        v.accept(this);
    }

    override void visit(const DoStmt v) {
        mixin(mixinNodeLog!());
        pushStack(ast.make!(analyze.Loop), v);
        v.accept(this);
    }

    override void visit(const SwitchStmt v) {
        mixin(mixinNodeLog!());
        auto n = ast.make!(analyze.BranchBundle);
        pushStack(n, v);
        v.accept(this);

        auto caseVisitor = new FindVisitor!CaseStmt;
        v.accept(caseVisitor);

        if (caseVisitor.node is null) {
            logger.warning(
                    "switch without any case statements may result in a high number of mutant scheman that do not compile");
        } else {
            incr;
            scope (exit)
                decr;
            auto block = ast.make!(analyze.Block);
            auto l = ast.location(n);
            l.interval.end = l.interval.begin;
            pushStack(block, l, CXCursorKind.unexposedDecl);
            rewriteSwitch(ast, n, block, caseVisitor.node.cursor.toLocation);
        }
    }

    override void visit(const ConditionalOperator v) {
        // ternery operator. It is hard to create a schema that have the
        // correct type on both rhs and lhs. for now just block scheman inside
        // ternery.
        auto n = ast.make!(analyze.Poision);
        n.schemaBlacklist = true;
        pushStack(n, v);
        v.accept(this);
    }

    override void visit(const IfStmt v) @trusted {
        mixin(mixinNodeLog!());
        pushStack(ast.make!(analyze.BranchBundle), v);
        dextool.plugin.mutate.backend.analyze.extensions.accept(v, this);
    }

    override void visit(const IfStmtCond v) {
        mixin(mixinNodeLog!());

        auto n = ast.make!(analyze.Condition);
        pushStack(n, v);

        if (!visitOp(v, v.cursor.kind)) {
            v.accept(this);
        }

        if (!n.children.empty) {
            auto tyId = ast.typeId(n.children[0]);
            if (tyId.hasValue) {
                ast.put(n, tyId.orElse(analyze.TypeId.init));
            }
        }

        rewriteCondition(ast, n);
    }

    override void visit(const IfStmtThen v) {
        mixin(mixinNodeLog!());
        visitIfBranch(v);
    }

    override void visit(const IfStmtElse v) {
        mixin(mixinNodeLog!());
        visitIfBranch(v);
    }

    private void visitIfBranch(T)(ref const T v) @trusted {
        pushStack(ast.make!(analyze.Branch), v);
        v.accept(this);
    }

    private bool visitOp(T)(ref const T v, const CXCursorKind cKind) @trusted {
        auto op = operatorCursor(ast.get, v);
        if (op.isNull) {
            return false;
        }

        if (visitBinaryOp(op.get, cKind))
            return true;
        return visitUnaryOp(op.get, cKind);
    }

    /// Returns: true if it added a binary operator, false otherwise.
    private bool visitBinaryOp(ref OperatorCursor op, const CXCursorKind cKind) @trusted {
        import libclang_ast.ast : dispatch;

        auto astOp = cast(analyze.BinaryOp) op.astOp;
        if (astOp is null)
            return false;

        const blockSchema = op.isOverload || blacklist.blockSchema(op.opLoc) || isParent(CXCursorKind.classTemplate,
                CXCursorKind.classTemplatePartialSpecialization, CXCursorKind.functionTemplate) != 0;

        astOp.schemaBlacklist = blockSchema;
        astOp.operator = op.operator;
        astOp.operator.blacklist = blacklist.inside(op.opLoc);
        astOp.operator.schemaBlacklist = blockSchema;

        op.put(nstack.back, ast);
        pushStack(astOp, op.exprLoc, cKind);
        incr;
        scope (exit)
            decr;

        if (op.lhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.lhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.lhs = b;
                auto ty = deriveCursorType(ast, op.lhs);
                ty.put(ast);
                if (ty.type !is null) {
                    ast.put(b, ty.id);
                }
                if (ty.symbol !is null) {
                    ast.put(b, ty.symId);
                }
            }
        }
        if (op.rhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.rhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.rhs = b;
                auto ty = deriveCursorType(ast, op.rhs);
                ty.put(ast);
                if (ty.type !is null) {
                    ast.put(b, ty.id);
                }
                if (ty.symbol !is null) {
                    ast.put(b, ty.symId);
                }
            }
        }

        // TODO: this is crude and shouldn't be here as a check but we must
        // block aor/rorp schematan when the type is a pointer.
        foreach (_; getChildrenTypes(ast, astOp).filter!(a => a.among(TypeKind.unordered,
                TypeKind.bottom))) {
            foreach (c; BreathFirstRange(astOp))
                c.schemaBlacklist = true;
            break;
        }

        return true;
    }

    /// Returns: true if it added a binary operator, false otherwise.
    private bool visitUnaryOp(ref OperatorCursor op, CXCursorKind cKind) @trusted {
        import libclang_ast.ast : dispatch;

        auto astOp = cast(analyze.UnaryOp) op.astOp;
        if (astOp is null)
            return false;

        const blockSchema = op.isOverload || blacklist.blockSchema(op.opLoc) || isParent(CXCursorKind.classTemplate,
                CXCursorKind.classTemplatePartialSpecialization, CXCursorKind.functionTemplate) != 0;

        astOp.operator = op.operator;
        astOp.operator.blacklist = blacklist.inside(op.opLoc);
        astOp.operator.schemaBlacklist = blockSchema;

        op.put(nstack.back, ast);
        pushStack(astOp, op.exprLoc, cKind);
        incr;
        scope (exit)
            decr;

        if (op.lhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.lhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.expr = b;
                auto ty = deriveCursorType(ast, op.lhs);
                ty.put(ast);
                if (ty.type !is null)
                    ast.put(b, ty.id);
                if (ty.symbol !is null)
                    ast.put(b, ty.symId);
            }
        }
        if (op.rhs.isValid) {
            incr;
            scope (exit)
                decr;
            dispatch(op.rhs, this);
            auto b = () {
                if (!lastDecr.empty)
                    return cast(analyze.Expr) lastDecr[$ - 1];
                return null;
            }();
            if (b !is null && b != astOp) {
                astOp.expr = b;
                auto ty = deriveCursorType(ast, op.rhs);
                ty.put(ast);
                if (ty.type !is null)
                    ast.put(b, ty.id);
                if (ty.symbol !is null)
                    ast.put(b, ty.symId);
            }
        }

        return true;
    }

    private void visitFunc(T)(ref const T v) @trusted {
        auto loc = v.cursor.toLocation;
        auto n = ast.make!(analyze.Function);
        n.schemaBlacklist = isConstExpr(v.cursor);
        nstack.back.children ~= n;
        pushStack(n, loc, v.cursor.kind);

        auto fRetval = ast.make!(analyze.Return);
        auto rty = deriveType(ast.get, v.cursor.func.resultType);
        rty.put(ast);
        if (rty.type !is null) {
            ast.put(fRetval, loc);
            n.return_ = fRetval;
            ast.put(fRetval, rty.id);
        }
        if (rty.symbol !is null)
            ast.put(fRetval, rty.symId);

        v.accept(this);
    }

    private void visitCall(T)(ref const T v) @trusted {
        auto n = ast.make!(analyze.Call);
        pushStack(n, v);

        auto ty = deriveType(ast.get, v.cursor.type);
        ty.put(ast);
        if (ty.type !is null)
            ast.put(n, ty.id);
        if (ty.symbol !is null)
            ast.put(n, ty.symId);

        v.accept(this);
    }
}

final class EnumVisitor : ExtendedVisitor {
    import libclang_ast.ast;

    alias visit = ExtendedVisitor.visit;

    mixin generateIndentIncrDecr;

    analyze.Ast* ast;
    analyze.TypeId id;
    Nullable!long minValue;
    Nullable!long maxValue;

    this(ref analyze.Ast ast, const uint indent) @trusted {
        this.ast = &ast;
        this.indent = indent;
    }

    override void visit(const EnumDecl v) @trusted {
        mixin(mixinNodeLog!());
        id = make!(analyze.TypeId)(v.cursor);
        v.accept(this);
    }

    override void visit(const EnumConstantDecl v) @trusted {
        mixin(mixinNodeLog!());

        long value = v.cursor.enum_.signedValue;

        if (minValue.isNull) {
            minValue = value;
            maxValue = value;
        }

        if (value < minValue.get)
            minValue = value;
        if (value > maxValue.get)
            maxValue = value;

        v.accept(this);
    }

    analyze.Type toType() {
        auto l = () {
            if (minValue.isNull)
                return analyze.Value(analyze.Value.NegInf.init);
            return analyze.Value(analyze.Value.Int(minValue.get));
        }();
        auto u = () {
            if (maxValue.isNull)
                return analyze.Value(analyze.Value.PosInf.init);
            return analyze.Value(analyze.Value.Int(maxValue.get));
        }();

        return ast.make!(analyze.DiscreteType)(analyze.Range(l, u));
    }
}

/// Find first occurences of the node type `T`.
final class FindVisitor(T) : Visitor {
    import libclang_ast.ast;

    alias visit = Visitor.visit;

    const(T)[] nodes;

    const(T) node() @safe pure nothrow const @nogc {
        if (nodes.empty)
            return null;
        return nodes[0];
    }

    //uint indent;
    //override void incr() @safe {
    //    ++indent;
    //}
    //
    //override void decr() @safe {
    //    --indent;
    //}

    override void visit(const Statement v) {
        //mixin(mixinNodeLog!());
        if (nodes.empty)
            v.accept(this);
    }

    override void visit(const T v) @trusted {
        //mixin(mixinNodeLog!());
        if (nodes.empty)
            nodes = [v];
    }
}

/** Rewrite the position of a condition to perfectly match the parenthesis.
 *
 * The source code:
 * ```
 * if (int x = 42) y = 43;
 * ```
 *
 * Results in something like this in the AST.
 *
 * `-Condition
 *   `-Expr
 *     `-Expr
 *       `-VarDecl
 *         `-OpGreater
 *           `-Operator
 *           `-Expr
 *           `-Expr
 *
 * The problem is that the location of the Condition node will be OpGreater and
 * not the VarDecl.
 */
void rewriteCondition(ref analyze.Ast ast, analyze.Condition root) {
    import sumtype;
    import dextool.plugin.mutate.backend.analyze.ast : TypeId, VarDecl, Kind;

    foreach (ty; BreathFirstRange(root).map!(a => ast.typeId(a))
            .filter!(a => a.hasValue)) {
        sumtype.match!((Some!TypeId a) => ast.put(root, a), (None a) {})(ty);
        break;
    }

    foreach (a; BreathFirstRange(root).filter!(a => a.kind == Kind.VarDecl)) {
        ast.put(root, ast.location(a));
        root.schemaBlacklist = true;
        a.schemaBlacklist = true;
        break;
    }
}

void rewriteSwitch(ref analyze.Ast ast, analyze.BranchBundle root,
        analyze.Block block, Location firstCase) {
    import std.range : enumerate;
    import std.typecons : tuple;

    Node[] beforeCase = root.children;
    Node[] rest;

    foreach (n; root.children
            .map!(a => tuple!("node", "loc")(a, ast.location(a)))
            .enumerate
            .filter!(a => a.value.loc.interval.begin > firstCase.interval.begin)) {
        beforeCase = root.children[0 .. n.index];
        rest = root.children[n.index .. $];
        break;
    }

    root.children = beforeCase ~ block;
    block.children = rest;
}

enum discreteCategory = AliasSeq!(CXTypeKind.charU, CXTypeKind.uChar, CXTypeKind.char16,
            CXTypeKind.char32, CXTypeKind.uShort, CXTypeKind.uInt, CXTypeKind.uLong, CXTypeKind.uLongLong,
            CXTypeKind.uInt128, CXTypeKind.charS, CXTypeKind.sChar, CXTypeKind.wChar, CXTypeKind.short_,
            CXTypeKind.int_, CXTypeKind.long_, CXTypeKind.longLong,
            CXTypeKind.int128, CXTypeKind.enum_,);
enum floatCategory = AliasSeq!(CXTypeKind.float_, CXTypeKind.double_,
            CXTypeKind.longDouble, CXTypeKind.float128, CXTypeKind.half, CXTypeKind.float16,);
enum pointerCategory = AliasSeq!(CXTypeKind.nullPtr, CXTypeKind.pointer,
            CXTypeKind.blockPointer, CXTypeKind.memberPointer, CXTypeKind.record);
enum boolCategory = AliasSeq!(CXTypeKind.bool_);

enum voidCategory = AliasSeq!(CXTypeKind.void_);

struct DeriveTypeResult {
    analyze.TypeId id;
    analyze.Type type;
    analyze.SymbolId symId;
    analyze.Symbol symbol;

    void put(ref analyze.Ast ast) @safe {
        if (type !is null) {
            ast.types.require(id, type);
        }
        if (symbol !is null) {
            ast.symbols.require(symId, symbol);
        }
    }
}

DeriveTypeResult deriveType(ref Ast ast, Type cty) {
    DeriveTypeResult rval;

    if (!cty.isValid)
        return rval;

    auto ctydecl = cty.declaration;
    if (ctydecl.isValid) {
        rval.id = make!(analyze.TypeId)(ctydecl);
    } else {
        rval.id = make!(analyze.TypeId)(cty.cursor);
    }

    if (cty.isEnum) {
        rval.type = ast.make!(analyze.DiscreteType)(analyze.Range.makeInf);
        if (!cty.isSigned) {
            rval.type.range.low = analyze.Value(analyze.Value.Int(0));
        }
    } else if (cty.kind.among(floatCategory)) {
        rval.type = ast.make!(analyze.ContinuesType)(analyze.Range.makeInf);
    } else if (cty.kind.among(pointerCategory)) {
        rval.type = ast.make!(analyze.UnorderedType)(analyze.Range.makeInf);
    } else if (cty.kind.among(boolCategory)) {
        rval.type = ast.make!(analyze.BooleanType)(analyze.Range.makeBoolean);
    } else if (cty.kind.among(discreteCategory)) {
        rval.type = ast.make!(analyze.DiscreteType)(analyze.Range.makeInf);
        if (!cty.isSigned) {
            rval.type.range.low = analyze.Value(analyze.Value.Int(0));
        }
    } else if (cty.kind.among(voidCategory)) {
        rval.type = ast.make!(analyze.VoidType)();
    } else {
        // unknown such as an elaborated
        rval.type = ast.make!(analyze.Type)();
    }

    return rval;
}

struct DeriveCursorTypeResult {
    Cursor expr;
    DeriveTypeResult typeResult;
    alias typeResult this;
}

/** Analyze a cursor to derive the type of it and if it has a concrete value
 * and what it is in that case.
 *
 * This is intended for expression nodes in the clang AST.
 */
DeriveCursorTypeResult deriveCursorType(ref Ast ast, const Cursor baseCursor) {
    auto c = Cursor(getUnderlyingExprNode(baseCursor));
    if (!c.isValid)
        return DeriveCursorTypeResult.init;

    auto rval = DeriveCursorTypeResult(c);
    auto cty = c.type.canonicalType;
    rval.typeResult = deriveType(ast, cty);

    // evaluate the cursor to add a value for the symbol
    void eval(const ref Eval e) {
        if (!e.kind.among(CXEvalResultKind.int_))
            return;

        const long value = () {
            if (e.isUnsignedInt) {
                const v = e.asUnsigned;
                if (v < long.max)
                    return cast(long) v;
            }
            return e.asLong;
        }();

        rval.symId = make!(analyze.SymbolId)(c);
        rval.symbol = ast.make!(analyze.DiscretSymbol)(analyze.Value(analyze.Value.Int(value)));
    }

    if (cty.isEnum) {
        // TODO: check if c.eval give the same result. If so it may be easier
        // to remove this special case of an enum because it is covered by the
        // generic branch for discretes.

        auto ctydecl = cty.declaration;
        if (!ctydecl.isValid)
            return rval;

        const cref = c.referenced;
        if (!cref.isValid)
            return rval;

        if (cref.kind == CXCursorKind.enumConstantDecl) {
            const long value = cref.enum_.signedValue;
            rval.symId = make!(analyze.SymbolId)(c);
            rval.symbol = ast.make!(analyze.DiscretSymbol)(
                    analyze.Value(analyze.Value.Int(value)));
        }
    } else if (cty.kind.among(discreteCategory)) {
        // crashes in clang 7.x. Investigate why.
        //const e = c.eval;
        //if (e.isValid)
        //    eval(e);
    }

    return rval;
}

auto make(T)(const Cursor c) if (is(T == analyze.TypeId) || is(T == analyze.SymbolId)) {
    const usr = c.usr;
    if (usr.empty) {
        return T(c.toHash);
    }
    return analyze.makeId!T(usr);
}

/// trusted: trusting the impl in clang.
uint findTokenOffset(T)(T toks, Offset sr, CXTokenKind kind) @trusted {
    foreach (ref t; toks) {
        if (t.location.offset >= sr.end) {
            if (t.kind == kind) {
                return t.extent.end.offset;
            }
            break;
        }
    }

    return sr.end;
}

/** Check if a function has the constexpr keyword.
 *
 * The implementation opt for higher precision than efficiency which is why it
 * looks at the tokens. That should eliminate such factors as "whitespace".
 */
bool isConstExpr(const Cursor c) @trusted {
    bool helper(T)(ref T toks) {
        foreach (ref t; toks.filter!(a => a.kind.among(CXTokenKind.keyword,
                CXTokenKind.identifier))) {
            if (t.spelling == "constexpr") {
                return true;
            }
        }
        return false;
    }

    auto toks = c.tokens;
    return helper(toks);
}

/** Create an index of all macros that then can be queried to see if a Cursor
 * or Interval overlap a macro.
 */
struct BlackList {
    import dextool.plugin.mutate.backend.analyze.utility : Index;

    Index!string macros;
    /// schemas are blacklisted for these
    Index!string schemas;

    this(const Cursor root) {
        Interval[][string] macros;
        Interval[][string] schemas;

        foreach (c, parent; root.all) {
            if (!c.kind.among(CXCursorKind.macroExpansion,
                    CXCursorKind.macroDefinition) || c.isMacroBuiltin)
                continue;

            auto spelling = c.spelling;
            // C code almost always implement these as macros. They should not
            // be blocked from being mutated.
            if (spelling.among("bool", "TRUE", "FALSE")) {
                add(c, schemas);
            } else {
                add(c, macros);
            }
        }

        foreach (k; macros.byKey) {
            macros[k] = macros[k].sort.array;
        }
        foreach (k; schemas.byKey) {
            schemas[k] = schemas[k].sort.array;
        }

        this.macros = Index!string(macros);
        this.schemas = Index!string(schemas);
    }

    static void add(const Cursor c, ref Interval[][string] idx) {
        const file = c.location.path;
        if (file.empty)
            return;
        const e = c.extent;
        const interval = Interval(e.start.offset, e.end.offset);
        if (auto v = file in idx) {
            (*v) ~= interval;
        } else {
            idx[file] = [interval];
        }
    }

    bool blockSchema(analyze.Location l) {
        return schemas.intersect(l.file, l.interval);
    }

    bool inside(const Cursor c) {
        const file = c.location.path.Path;
        const e = c.extent;
        const interval = Interval(e.start.offset, e.end.offset);
        return inside(file, interval);
    }

    bool inside(analyze.Location l) {
        return inside(l.file, l.interval);
    }

    /**
     * assuming that an invalid mutant is always inside a macro thus only
     * checking if the `i` is inside. Removing a "block" of code that happens
     * to contain a macro is totally "ok". It doesn't create any problem.
     *
     * Returns: true if `i` is inside a macro interval.
     */
    bool inside(const Path file, const Interval i) {
        return macros.overlap(file, i);
    }
}

/// Returns: the types of the children
auto getChildrenTypes(ref Ast ast, Node parent) {
    return BreathFirstRange(parent).map!(a => ast.type(a))
        .filter!(a => a !is null)
        .map!(a => a.kind);
}
