/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

A language independent AST specific for generating mutants both via the plain
source code manipulation but also mutant schematas.
*/
module dextool.plugin.mutate.backend.analyze.ast;

import logger = std.experimental.logger;
import std.algorithm : map, filter, among;
import std.array : Appender, appender, empty;
import std.exception : collectException;
import std.format : formattedWrite, format;
import std.meta : AliasSeq;
import std.range : isOutputRange;

import my.optional;
import sumtype;

import dextool.type : AbsolutePath, Path;

static import dextool.plugin.mutate.backend.type;

@safe:

struct Ast {
    import std.experimental.allocator.mallocator : Mallocator;

    /// The language the mutation AST is based on.
    dextool.plugin.mutate.backend.type.Language lang;

    Location[Node] locs;

    // a node can have a type
    TypeId[Node] nodeTypes;
    Types types;

    // a node can have been resolved to a symbolic value.
    SymbolId[Node] nodeSymbols;
    Symbols symbols;

    Node root;

    // Change the path and thus string in the saved locations to reduce the used memory.
    Dedup!AbsolutePath paths;

    private {
        static struct AllocObj {
            Object obj;
            size_t sz;
        }

        AllocObj[] dobjs;
    }

    ~this() nothrow {
        release;
    }

    T make(T, Args...)(auto ref Args args) {
        import core.memory : GC;
        import std.experimental.allocator : make;
        import std.functional : forward;

        auto obj = () @trusted {
            return make!T(Mallocator.instance, forward!args);
        }();
        enum sz = __traits(classInstanceSize, T);
        () @trusted {
            auto repr = (cast(void*) obj)[0 .. sz];
            GC.addRange(&repr[(void*).sizeof], sz - (void*).sizeof);
        }();

        dobjs ~= AllocObj(obj, sz);
        return obj;
    }

    /// Release all nodes by destroying them and releasing the memory
    void release() nothrow @trusted {
        import core.memory : GC;
        import std.experimental.allocator : dispose;

        if (!dobjs.empty) {
            if (auto v = root in locs)
                logger.tracef("released AST for %s with objects %s", v.file,
                        dobjs.length).collectException;
            else
                logger.tracef("released AST with %s objects", dobjs.length).collectException;
        }

        auto allocator = Mallocator.instance;
        foreach (n; dobjs) {
            dispose(allocator, n.obj);
            auto repr = (cast(void*) n.obj)[0 .. n.sz];
            GC.removeRange(&repr[(void*).sizeof]);
        }

        dobjs = null;
        paths = typeof(paths).init;
        nodeTypes = null;
        nodeSymbols = null;
        locs = null;
    }

    void releaseCache() {
        paths.release;
    }

    void accept(VisitorT)(VisitorT v) {
        v.visit(root);
    }

    void put(Node n, Location l) {
        // TODO: deduplicate the path because it will otherwise take up so much
        // memory.....
        l.file = paths.dedup(l.file);
        locs[n] = l;
    }

    void put(Node n, TypeId id) {
        nodeTypes[n] = id;
    }

    void put(Node n, SymbolId id) {
        nodeSymbols[n] = id;
    }

    Location location(Node n) {
        if (auto v = n in locs) {
            return *v;
        }
        return Location.init;
    }

    Type type(Node n) {
        if (auto v = n in nodeTypes) {
            return types.get(*v);
        }
        return null;
    }

    Optional!TypeId typeId(Node n) {
        if (auto v = n in nodeTypes) {
            return some(*v);
        }
        return none!TypeId;
    }

    Symbol symbol(Node n) {
        if (auto v = n in nodeSymbols) {
            return symbols.get(*v);
        }
        return null;
    }

    string toString() @safe {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        import std.range : put;

        formattedWrite(w, "Source language: %s\n", lang);

        auto res = () @trusted {
            scope dump = new AstPrintVisitor(&this);
            this.accept(dump);
            return dump.buf.data;
        }();
        put(w, res);

        put(w, "Types:");
        put(w, "\n");
        types.toString(w);
        put(w, "Symbols:");
        put(w, "\n");
        symbols.toString(w);
    }
}

class AstPrintVisitor : DepthFirstVisitor {
    import std.range : put, repeat;

    Appender!string buf;
    int depth;
    int prevDepth;
    char[] indent;
    Ast* ast;

    this(Ast* ast) {
        this.ast = ast;
    }

    void toBuf(Node n) {
        import std.conv : to;
        import colorlog : color, Color;

        if (depth == 0) {
            indent = null;
        } else if (depth == prevDepth) {
        } else if (depth > prevDepth) {
            const diff = (depth - prevDepth - 1) * 2;
            if (indent.length == 0) {
            } else if (indent[$ - 2] == '`') {
                indent[$ - 1] = ' ';
                indent[$ - 2] = ' ';
            } else {
                indent[$ - 1] = ' ';
            }

            foreach (_; 0 .. diff)
                indent ~= "  ";

            if (n.children.length <= 1)
                indent ~= "`-";
            else
                indent ~= "|-";
        } else {
            const diff = (prevDepth - depth) * 2;
            indent = indent[0 .. $ - diff];

            if (indent.length != 0 && indent[$ - 2 .. $] == "| ") {
                indent[$ - 1] = '-';
            }
        }
        put(buf, indent);

        void printNode() {
            auto bl = () {
                if (n.blacklist)
                    return " blacklist".color(Color.magenta).toString;
                return "";
            }();
            auto schemaBl = () {
                if (n.schemaBlacklist)
                    return " !schema".color(Color.magenta).toString;
                return "";
            }();
            formattedWrite(buf, "%s %s%s%s",
                    n.kind.to!string.color(Color.lightGreen),
                    n.id.to!string.color(Color.lightYellow), bl, schemaBl);
        }

        void printTypeSymbol(Node n) {
            if (auto tyId = n in ast.nodeTypes) {
                auto ty = ast.types.get(*tyId);
                formattedWrite(buf, " %X", tyId.value);
            }
            if (auto syId = n in ast.nodeSymbols) {
                auto sy = ast.symbols.get(*syId);
                formattedWrite(buf, " %X:%s", syId.value, sy.value);
            }
        }

        switch (n.kind) {
        case Kind.Function:
            printNode;
            printTypeSymbol((cast(Function) n).return_);
            break;
        case Kind.VarDecl:
            printNode;
            if ((cast(VarDecl) n).isConst) {
                put(buf, " const");
            }
            break;
        default:
            printNode;
            if (isExpression(n.kind)) {
                printTypeSymbol(n);
            }
        }

        if (auto l = ast.location(n)) {
            formattedWrite(buf, " <%s:%s>", l.file.color(Color.cyan), l.posToString);
        }
        put(buf, "\n");

        prevDepth = depth;
    }

    static foreach (N; Nodes) {
        override void visit(N n) {
            toBuf(n);
            ++depth;

            auto op = () @trusted {
                if (auto v = cast(BinaryOp) n) {
                    return v.operator;
                } else if (auto v = cast(UnaryOp) n) {
                    return v.operator;
                }
                return null;
            }();
            if (op !is null) {
                visit(op);
            }

            accept(n, this);
            --depth;
        }
    }
}

/// The interval in bytes that the node occupy. It is a closed->open set.
alias Interval = dextool.plugin.mutate.backend.type.Offset;
alias SourceLoc = dextool.plugin.mutate.backend.type.SourceLoc;
alias SourceLocRange = dextool.plugin.mutate.backend.type.SourceLocRange;

struct Location {
    import std.range : isOutputRange;

    AbsolutePath file;
    Interval interval;
    SourceLocRange sloc;

    this(Path f, Interval i, SourceLocRange s) {
        file = f;
        interval = i;
        sloc = s;
    }

    T opCast(T : bool)() @safe pure const nothrow {
        return !file.empty;
    }

    // Convert only the position in the file to a string.
    string posToString() @safe const {
        return format!"[%s:%s-%s:%s]:[%s:%s]"(sloc.begin.line, sloc.begin.column,
                sloc.end.line, sloc.end.column, interval.begin, interval.end);
    }

    string toString() @safe const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;

        formattedWrite!"%s:%s"(w, file, posToString);
    }
}

private ulong uniqueNodeId() {
    static ulong next;
    return next++;
}

abstract class Node {
    Kind kind() const;
    ulong id() @safe pure nothrow const @nogc;

    Node[] children;

    /** If the node is blacklisted from being mutated. This is for example when
     * the node covers a C macro.
     */
    bool blacklist;

    /** If the node should not be part of mutant schemata because it is highly
     * likely to introduce compilation errors. It is for example likely when
     * operators are overloaded.
     */
    bool schemaBlacklist;

    bool opEquals(Kind k) {
        return kind == k;
    }

    override bool opEquals(Object o) {
        auto rhs = cast(const Node) o;
        return (rhs && (id == rhs.id));
    }

    override size_t toHash() @safe pure nothrow const @nogc scope {
        return id.hashOf();
    }
}

/**
 * It is optional to add the members visitPush/visitPop to push/pop the nodes that are visited.
 * The parent will always have been the last pushed.
 */
void accept(VisitorT)(Node n, VisitorT v) {
    static string mixinSwitch() {
        import std.conv : text;
        import std.traits : EnumMembers;

        string s;
        s ~= "final switch(c.kind) {\n";
        foreach (kind; [EnumMembers!Kind]) {
            const k = text(kind);
            s ~= format!"case Kind." ~ k ~ ": v.visit(cast(" ~ k ~ ") c); break;\n";
        }
        s ~= "}";
        return s;
    }

    static if (__traits(hasMember, VisitorT, "visitPush"))
        v.visitPush(n);
    foreach (c; n.children) {
        mixin(mixinSwitch);
    }

    static if (__traits(hasMember, VisitorT, "visitPop"))
        v.visitPop(n);
}

/// All nodes that a visitor must be able to handle.
// must be sorted such that the leaf nodes are at the top.
// dfmt off
alias Nodes = AliasSeq!(
    BinaryOp,
    Block,
    Branch,
    BranchBundle,
    Call,
    Condition,
    Constructor,
    Expr,
    Function,
    Loop,
    Node,
    OpAdd,
    OpAnd,
    OpAndBitwise,
    OpAssign,
    OpAssignAdd,
    OpAssignAndBitwise,
    OpAssignDiv,
    OpAssignMod,
    OpAssignMul,
    OpAssignOrBitwise,
    OpAssignSub,
    OpDiv,
    OpEqual,
    OpGreater,
    OpGreaterEq,
    OpLess,
    OpLessEq,
    OpMod,
    OpMul,
    OpNegate,
    OpNotEqual,
    OpOr,
    OpOrBitwise,
    OpSub,
    Operator,
    Poision,
    Return,
    Statement,
    TranslationUnit,
    UnaryOp,
    VarDecl,
    VarRef,
);

// It should be possible to generate the enum from Nodes. How?
enum Kind {
    BinaryOp,
    Block,
    Branch,
    BranchBundle,
    Call,
    Condition,
    Constructor,
    Expr,
    Function,
    Loop,
    Node,
    OpAdd,
    OpAnd,
    OpAndBitwise,
    OpAssign,
    OpAssignAdd,
    OpAssignAndBitwise,
    OpAssignDiv,
    OpAssignMod,
    OpAssignMul,
    OpAssignOrBitwise,
    OpAssignSub,
    OpDiv,
    OpEqual,
    OpGreater,
    OpGreaterEq,
    OpLess,
    OpLessEq,
    OpMod,
    OpMul,
    OpNegate,
    OpNotEqual,
    OpOr,
    OpOrBitwise,
    OpSub,
    Operator,
    Poision,
    Return,
    Statement,
    TranslationUnit,
    UnaryOp,
    VarDecl,
    VarRef,
}

alias ExpressionKind = AliasSeq!(
    Kind.BinaryOp,
    Kind.Call,
    Kind.Condition,
    Kind.Constructor,
    Kind.Expr,
    Kind.OpAdd,
    Kind.OpAnd,
    Kind.OpAndBitwise,
    Kind.OpAssign,
    Kind.OpDiv,
    Kind.OpEqual,
    Kind.OpGreater,
    Kind.OpGreaterEq,
    Kind.OpLess,
    Kind.OpLessEq,
    Kind.OpMod,
    Kind.OpMul,
    Kind.OpNegate,
    Kind.OpNotEqual,
    Kind.OpOr,
    Kind.OpOrBitwise,
    Kind.OpSub,
    Kind.Return,
    Kind.UnaryOp,
    Kind.VarDecl,
    Kind.VarRef,
);
// dfmt on

bool isExpression(Kind k) @safe pure nothrow @nogc {
    return k.among(ExpressionKind) != 0;
}

interface Visitor {
    static foreach (N; Nodes) {
        void visit(N);
    }
}

// TODO: implement a breath first.
class DepthFirstVisitor : Visitor {
    int visitDepth;

    void visitPush(Node n) {
    }

    void visitPop(Node n) {
    }

    static foreach (N; Nodes) {
        override void visit(N n) {
            ++visitDepth;
            accept(n, this);
            --visitDepth;
        }
    }
}

/** A phantom node that carry semantic information about its children. It
 * "poisons" all children.
 */
class Poision : Node {
    mixin(nodeImpl!(typeof(this)));
}

class TranslationUnit : Node {
    mixin(nodeImpl!(typeof(this)));
}

class Statement : Node {
    mixin(nodeImpl!(typeof(this)));
}

class Loop : Node {
    mixin(nodeImpl!(typeof(this)));
}

class Expr : Node {
    mixin(nodeImpl!(typeof(this)));
}

/// A function definition.
class Function : Node {
    mixin(nodeImpl!(typeof(this)));

    /// If the function has a return type it is associated with this expression.
    Return return_;
}

/// A constructor for a variable.
class Constructor : Expr {
    mixin(nodeImpl!(typeof(this)));
}

/// A function call.
class Call : Expr {
    mixin(nodeImpl!(typeof(this)));
}

/// The operator itself in a binary operator expression.
class Operator : Node {
    mixin(nodeImpl!(typeof(this)));
}

/** A block of code such such as a local scope enclosed by brackets, `{}`.
 *
 * It is intended to be possible to delete it. But it may need to be further
 * analyzed for e.g. `Return` nodes.
 */
class Block : Node {
    mixin(nodeImpl!(typeof(this)));
}

/** Multiple branches are contained in the bundle that can be e.g. deleted.
 *
 * This can, in C/C++, be either a whole if-statement or switch.
 */
class BranchBundle : Node {
    mixin(nodeImpl!(typeof(this)));
}

/** The code for one of the branches resulting from a condition.
 *
 * It can be the branches in a if-else statement or a case branch for languages
 * such as C/C++.
 *
 * The important aspect is that the branch is not an expression. It can't be
 * evaluated to a value of a type.
 */
class Branch : Node {
    mixin(nodeImpl!(typeof(this)));

    // The inside of a branch node wherein code can be injected.
    Block inside;
}

/// Results in the bottom type or up.
class Return : Expr {
    mixin(nodeImpl!(typeof(this)));
}

/// A condition wraps "something" which always evaluates to a boolean.
class Condition : Expr {
    mixin(nodeImpl!(typeof(this)));
}

class VarDecl : Expr {
    mixin(nodeImpl!(typeof(this)));
    bool isConst;
}

class VarRef : Expr {
    mixin(nodeImpl!(typeof(this)));
    // should always refer to something
    VarDecl to;

    this(VarDecl to) {
        this();
        this.to = to;
    }

    invariant {
        assert(to !is null);
    }
}

class UnaryOp : Expr {
    mixin(nodeImpl!(typeof(this)));

    Operator operator;
    Expr expr;

    this(Operator op, Expr expr) {
        this();
        this.operator = op;
        this.expr = expr;
    }
}

class OpNegate : UnaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class BinaryOp : Expr {
    mixin(nodeImpl!(typeof(this)));

    Operator operator;
    Expr lhs;
    Expr rhs;

    this(Operator op, Expr lhs, Expr rhs) {
        this();
        this.operator = op;
        this.lhs = lhs;
        this.rhs = rhs;
    }
}

class OpAssign : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAssignAdd : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAssignSub : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAssignMul : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAssignDiv : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAssignMod : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAssignAndBitwise : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAssignOrBitwise : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAdd : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpSub : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpMul : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpDiv : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpMod : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAnd : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpAndBitwise : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpOr : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpOrBitwise : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpEqual : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpLess : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpGreater : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpLessEq : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpGreaterEq : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

class OpNotEqual : BinaryOp {
    mixin(nodeImpl!(typeof(this)));
}

RetT makeId(RetT, T)(T data) {
    import my.hash : makeCrc64Iso;

    auto a = makeCrc64Iso(cast(const(ubyte)[]) data);
    return RetT(a.c0);
}

RetT makeUniqueId(RetT)() {
    import std.random : uniform;

    return RetT(uniform(long.min, long.max));
}

class Type {
    private const ulong id_;

    Range range;

    this() {
        this(Range.makeInf);
    }

    this(Range r) {
        this.range = r;
        id_ = uniqueNodeId;
    }

    TypeKind kind() const {
        return TypeKind.bottom;
    }

    ulong id() @safe pure nothrow const @nogc {
        return id_;
    }

    override bool opEquals(Object o) {
        auto rhs = cast(const Type) o;
        return (rhs && (id == rhs.id));
    }

    override size_t toHash() @safe pure nothrow const @nogc scope {
        return id.hashOf();
    }
}

final class DiscreteType : Type {
    this(Range r) {
        super(r);
    }

    override TypeKind kind() const {
        return TypeKind.discrete;
    }
}

final class ContinuesType : Type {
    this(Range r) {
        super(r);
    }

    override TypeKind kind() const {
        return TypeKind.continues;
    }
}

final class UnorderedType : Type {
    this(Range r) {
        super(r);
    }

    override TypeKind kind() const {
        return TypeKind.unordered;
    }
}

final class BooleanType : Type {
    this(Range r) {
        super(r);
    }

    override TypeKind kind() const {
        return TypeKind.boolean;
    }
}

final class VoidType : Type {
    this() {
        super();
    }

    override TypeKind kind() const {
        return TypeKind.top;
    }
}

enum TypeKind {
    // It can be anything, practically useless for mutation testing because it
    // doesn't provide any logic that can be used to e.g. generate
    // "intelligent" ROR mutants.
    bottom,
    /// integers, enums
    discrete,
    /// floating point values
    continues,
    /// no order exists between values in the type thus unable to do ROR
    unordered,
    ///
    boolean,
    /// a top type is nothing
    top,
}

struct Value {
    import std.traits : TemplateArgsOf;

    static struct NegInf {
    }

    static struct PosInf {
    }

    static struct Int {
        // TODO: change to BigInt?
        long value;
    }

    static struct Bool {
        bool value;
    }

    alias Value = SumType!(NegInf, PosInf, Int, Bool);
    Value value;

    static foreach (T; TemplateArgsOf!Value) {
        this(T a) {
            value = Value(a);
        }
    }

    string toString() @safe pure const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.conv : to;
        import std.range : put;

        value.match!((const NegInf a) => put(w, "-inf"), (const PosInf a) => put(w,
                "+inf"), (const Int a) => put(w, a.value.to!string),
                (const Bool a) => put(w, a.value.to!string));
    }
}

struct Range {
    static makeInf() {
        return Range(Value(Value.NegInf.init), Value(Value.PosInf.init));
    }

    static makeBoolean() {
        return Range(Value(Value.Bool(false)), Value(Value.Bool(true)));
    }

    Value low;
    Value up;

    this(Value low, Value up) {
        this.low = low;
        this.up = up;
    }

    enum CompareResult {
        onLowerBound,
        onUpperBound,
        // the value and the range fully overlap each other. This happens when
        // the range is only one value.
        overlap,
        inside,
        outside
    }

    CompareResult compare(Value v) {
        CompareResult negInf() {
            return low.value.match!((Value.NegInf a) => CompareResult.onLowerBound,
                    (Value.PosInf a) => CompareResult.outside,
                    (Value.Int a) => CompareResult.outside, (Value.Bool a) => CompareResult.outside);
        }

        CompareResult posInf() {
            return up.value.match!((Value.NegInf a) => CompareResult.onUpperBound,
                    (Value.PosInf a) => CompareResult.outside,
                    (Value.Int a) => CompareResult.outside, (Value.Bool a) => CompareResult.outside);
        }

        CompareResult value(long v) {
            const l = low.value.match!((Value.NegInf a) => CompareResult.inside,
                    (Value.PosInf a) => CompareResult.outside, (Value.Int a) {
                if (a.value < v)
                    return CompareResult.inside;
                if (a.value == v)
                    return CompareResult.onLowerBound;
                return CompareResult.outside;
            }, (Value.Bool a) => CompareResult.outside);

            const u = up.value.match!((Value.NegInf a) => CompareResult.outside,
                    (Value.PosInf a) => CompareResult.inside, (Value.Int a) {
                if (a.value > v)
                    return CompareResult.inside;
                if (a.value == v)
                    return CompareResult.onUpperBound;
                return CompareResult.outside;
            }, (Value.Bool a) => CompareResult.outside);

            if (l == CompareResult.inside && u == CompareResult.inside)
                return CompareResult.inside;
            if (l == CompareResult.onLowerBound && u == CompareResult.onUpperBound)
                return CompareResult.overlap;
            if (l == CompareResult.onLowerBound)
                return l;
            if (u == CompareResult.onUpperBound)
                return u;
            assert(l == CompareResult.outside || u == CompareResult.outside);
            return CompareResult.outside;
        }

        CompareResult boolean(bool v) {
            // TODO: fix this
            return CompareResult.outside;
        }

        return v.value.match!((Value.NegInf a) => negInf,
                (Value.PosInf a) => posInf, (Value.Int a) => value(a.value),
                (Value.Bool a) => boolean(a.value));
    }

    string toString() @safe pure const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.range : put;

        put(w, "[");
        low.toString(w);
        put(w, ":");
        up.toString(w);
        put(w, "]");
    }
}

struct TypeId {
    ulong value;

    size_t toHash() @safe pure nothrow const @nogc {
        return value.hashOf;
    }
}

TypeId makeTypeId(T)(T data) {
    return makeId!TypeId(data);
}

TypeId makeUniqueTypeId() {
    return makeUniqueId!TypeId;
}

struct Types {
    Type[TypeId] types;

    void require(TypeId id, Type t) {
        if (id !in types) {
            types[id] = t;
        }
    }

    void set(TypeId id, Type t) {
        types[id] = t;
    }

    Type get(TypeId id) {
        if (auto v = id in types) {
            return *v;
        }
        return null;
    }

    bool hasId(TypeId id) {
        return (id in types) !is null;
    }

    string toString() @safe const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;
        import std.range : put;

        foreach (kv; types.byKeyValue) {
            formattedWrite(w, "%X:%s:%s", kv.key.value, kv.value.kind, kv.value.range);
            put(w, "\n");
        }
    }
}

class Symbol {
    Value value;

    this() {
        this(Value(Value.PosInf.init));
    }

    this(Value v) {
        this.value = v;
    }

    SymbolKind kind() const {
        return SymbolKind.unknown;
    }
}

final class DiscretSymbol : Symbol {
    this(Value r) {
        super(r);
    }

    override SymbolKind kind() const {
        return SymbolKind.discret;
    }
}

final class ContinuesSymbol : Symbol {
    this(Value r) {
        super(r);
    }

    override SymbolKind kind() const {
        return SymbolKind.continues;
    }
}

final class BooleanSymbol : Symbol {
    this(Value r) {
        super(r);
    }

    override SymbolKind kind() const {
        return SymbolKind.boolean;
    }
}

enum SymbolKind {
    /// the symbol wasn't able to evaluate to something useful
    unknown,
    /// integers, enums
    discret,
    /// floating point values
    continues,
    ///
    boolean,
}

struct SymbolId {
    ulong value;

    size_t toHash() @safe pure nothrow const @nogc {
        return value.hashOf;
    }
}

SymbolId makeSymbolId(T)(T data) {
    return makeId!SymbolId(data);
}

SymbolId makeUniqueSymbolId() {
    return makeUniqueId!SymbolId;
}

struct Symbols {
    Symbol[SymbolId] symbols;

    void require(SymbolId id, Symbol s) {
        if (id !in symbols) {
            symbols[id] = s;
        }
    }

    void set(SymbolId id, Symbol s) {
        symbols[id] = s;
    }

    Symbol get(SymbolId id) {
        if (auto v = id in symbols) {
            return *v;
        }
        return null;
    }

    bool hasId(SymbolId id) {
        return (id in symbols) !is null;
    }

    string toString() @safe const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        foreach (kv; symbols.byKeyValue) {
            formattedWrite(w, "%X:%s:%s\n", kv.key.value, kv.value.kind, kv.value.value);
        }
    }
}

struct RecurseRange {
    import my.container.vector;

    Vector!Node nodes;

    this(Node n) {
        nodes.put(n);
    }

    Node front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return nodes.front;
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        nodes.put(nodes.front.children);
        nodes.popFront;
    }

    bool empty() @safe pure nothrow const @nogc {
        return nodes.empty;
    }
}

private:

string nodeImpl(T)() {
    return `
    private const ulong id_;

    override ulong id() @safe pure nothrow const @nogc { return id_; }

    override Kind kind() const {
        return Kind.` ~ T.stringof ~ `;
    }

    this() {
        id_ = uniqueNodeId;
    }`;
}

string typeImpl() {
    return `
    private const ulong id_;
    override ulong id() @safe pure nothrow const @nogc { return id_; }
    this() {
        id_ = uniqueNodeId;
    }`;
}

/// Dedup the paths to reduce the required memory.
struct Dedup(T) {
    T[ulong] cache;
    /// Number of deduplications.
    long count;
    /// ".length" accumulated of items deduplicated.
    long lengthAccum;

    T dedup(T p) {
        import std.traits : hasMember;

        const cs = p.toHash;
        if (auto v = cs in cache) {
            ++count;
            static if (hasMember!(T, "length"))
                lengthAccum += p.length;
            return *v;
        }

        cache[cs] = p;
        return p;
    }

    void release() {
        cache = typeof(cache).init;
    }
}
