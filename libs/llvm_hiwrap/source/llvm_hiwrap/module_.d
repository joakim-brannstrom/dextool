/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Modules represent the top-level structure in an LLVM program. An LLVM module is
effectively a translation unit or a collection of translation units merged
together.
*/
module llvm_hiwrap.module_;

import llvm : LLVMVerifyModule, LLVMModuleCreateWithName, LLVMModuleRef,
    LLVMDisposeModule, LLVMBool, LLVMVerifierFailureAction, LLVMGetModuleIdentifier;

import llvm_hiwrap.util : toD;
import llvm_hiwrap.types; // : LxVerifierFailureAction, LxMessage;
import llvm_hiwrap.value.function_;

import std.conv : to;
import std.string : toStringz;
import std.typecons : NullableRef;

struct Module {
    import llvm_hiwrap.value.metadata : NamedMetadataValue;

    LLVMModuleRef lx;
    alias lx this;

    @disable this();
    // if a refcount is used instead this could be removed.
    @disable this(this);

    this(LLVMModuleRef m) {
        this.lx = m;
    }

    /** Create a new, empty module in the global context.
     */
    this(string module_id) {
        const(char)* s = module_id.toStringz;
        lx = LLVMModuleCreateWithName(s);
    }

    ~this() {
        LLVMDisposeModule(lx);
    }

    /** Verifies that a module is valid.
     *
     * Optionally returns a human-readable description of any invalid
     * constructs. OutMessage must be disposed with LLVMDisposeMessage.
     */
    VerifyResult verify() {
        LxMessage msg;
        auto action = LxVerifierFailureAction.ReturnStatusAction.to!LLVMVerifierFailureAction;
        LLVMBool res = LLVMVerifyModule(lx, action, &msg.rawPtr);

        return VerifyResult(res == 0, msg.toD);
    }

    /** Obtain the identifier of the module.
     */
    const(char)[] identifier() {
        import llvm : LLVMGetModuleIdentifier;

        size_t len;
        auto str = LLVMGetModuleIdentifier(lx, &len);
        return str[0 .. len];
    }

    void identifier(string module_id) {
        import llvm : LLVMSetModuleIdentifier;

        LLVMSetModuleIdentifier(lx, module_id.ptr, module_id.length);
    }

    FunctionRange functions() {
        return FunctionRange(NullableRef!Module(&this));
    }

    /// Returns: Obtain a Function value from a Module by its name.
    FunctionValue func(string name) {
        import std.string : toStringz;
        import llvm : LLVMGetNamedFunction;
        import llvm_hiwrap;

        auto s = name.toStringz;
        auto v = LLVMGetNamedFunction(lx, cast(const(char)*) s);
        return v.LxValue.LxUserValue.LxFunctionValue.FunctionValue;
    }

    /** Writes a module to a new memory buffer and returns it. */
    auto toBuffer() @trusted {
        import llvm : LLVMMemoryBufferRef, LLVMWriteBitcodeToMemoryBuffer;
        import llvm_hiwrap.buffer : MemoryBuffer;

        LLVMMemoryBufferRef buf = LLVMWriteBitcodeToMemoryBuffer(lx);
        return MemoryBuffer(buf);
    }

    /** Obtain the named metadata operands for a module.
     *
     * @see llvm::Module::getNamedMetadata()
     * @see llvm::MDNode::getOperand()
     */
    NamedMetadataValue namedMetadata(string name) {
        import std.array : array;
        import std.algorithm : map;
        import llvm;

        LLVMValueRef[] ops;
        auto name_ = name.toStringz;
        ops.length = LLVMGetNamedMetadataNumOperands(lx, name_);

        if (ops.length != 0) {
            LLVMGetNamedMetadataOperands(lx, name_, ops.ptr);
        }

        NamedMetadataValue nmd;
        nmd.operands = ops.map!(a => a.LxValue.LxNamedMetadataNodeValue).array();

        return nmd;
    }

    /** Add an operand to named metadata.
     *
     * @see llvm::Module::getNamedMetadata()
     * @see llvm::MDNode::addOperand()
     */
    //void LLVMAddNamedMetadataOperand(LLVMModuleRef M, const char *Name,
    //                                 LLVMValueRef Val);

    import std.format : FormatSpec;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) {
        import std.format : formatValue;
        import std.range.primitives : put;
        import llvm : LLVMPrintModuleToString;

        () @trusted {
            auto msg = LxMessage(LLVMPrintModuleToString(lx));
            put(w, msg.toChar);
        }();
    }

    string toString() @safe {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
}

@("the ModuleID shall be changed")
unittest {
    import llvm_hiwrap.context;

    auto ctx = Context.make;

    auto m = ctx.makeModule("foo");
    assert(m.identifier == "foo");

    m.identifier = "bar";
    assert(m.identifier == "bar");
}

struct FunctionRange {
    import llvm;
    import llvm_hiwrap;

    private FunctionValue cur;
    private const LLVMValueRef end;

    this(NullableRef!Module parent) {
        cur = LLVMGetFirstFunction(parent.lx).LxValue.LxUserValue.LxFunctionValue.FunctionValue;
        end = LLVMGetLastFunction(parent.lx);
    }

    FunctionValue front() {
        assert(!empty, "Can't get front of an empty range");
        return cur;
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");
        cur = LLVMGetNextFunction(cur).LxValue.LxUserValue.LxFunctionValue.FunctionValue;
    }

    bool empty() {
        return cur == end;
    }
}

mixin template ModuleAccept(VisitorT, UserT) {
    import llvm_hiwrap.module_;

    void implAccept(ref Module n) {
        import llvm_hiwrap.ast.tree;

        foreach (func; n.functions) {
            maybeCallVisit(this, user, func);
        }
    }
}

/** A depth-first visitor.
 *
 * See: llvm_hiwrap.ast.tree
 *
 * Accepted node types are:
 *  - Module
 *
 * and those specified in:
 * See: llvm_hiwrap.value.function_
 * See: llvm_hiwrap.value.basic_block
 */
struct ModuleVisitor(UserT) {
    import llvm_hiwrap.value.basic_block : BasicBlockAccept;
    import llvm_hiwrap.value.function_ : FunctionAccept;

    UserT user;

    void visit(ref Module n) {
        import llvm_hiwrap.ast.tree;

        static void fallback(T)(ref this self, ref UserT user, ref T node) {
            accept(n, self);
        }

        maybeCallVisit(this, user, n);
    }

    mixin ModuleAccept!(ModuleVisitor, UserT);
    mixin FunctionAccept!(ModuleVisitor, UserT);
    mixin BasicBlockAccept!(ModuleVisitor, UserT);
}

@("shall instantiate a ModuleVisitor")
unittest {
    import llvm_hiwrap.ast.tree;
    import llvm_hiwrap.context;

    auto ctx = Context.make;

    auto m = ctx.makeModule("foo");

    struct Null {
    }

    ModuleVisitor!Null v;
}

private:

struct VerifyResult {
    const bool isValid;
    const string errorMsg;
}
