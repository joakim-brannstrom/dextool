/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

# LxValue
The following is copied from llvm-c/Core.h

The bulk of LLVM's object model consists of values, which comprise a very
rich type hierarchy.

LLVMValueRef essentially represents llvm::Value. There is a rich
hierarchy of classes within this type. Depending on the instance
obtained, not all APIs are available.

Callers can determine the type of an LLVMValueRef by calling the
LLVMIsA* family of functions (e.g. LLVMIsAArgument()). These
functions are defined by a macro, so it isn't obvious which are
available by looking at the Doxygen source code. Instead, look at the
source definition of LLVM_FOR_EACH_VALUE_SUBCLASS and note the list
of value names given. These value names also correspond to classes in
the llvm::Value hierarchy.

  macro(Argument)
  macro(BasicBlock)
  macro(InlineAsm)
  macro(User)
    macro(Constant)
      macro(BlockAddress)
      macro(ConstantAggregateZero)
      macro(ConstantArray)
      macro(ConstantDataSequential)
        macro(ConstantDataArray)
        macro(ConstantDataVector)
      macro(ConstantExpr)
      macro(ConstantFP)
      macro(ConstantInt)
      macro(ConstantPointerNull)
      macro(ConstantStruct)
      macro(ConstantTokenNone)
      macro(ConstantVector)
      macro(GlobalValue)
        macro(GlobalAlias)
        macro(GlobalObject)
          macro(Function)
          macro(GlobalVariable)
      macro(UndefValue)
    macro(Instruction)
      macro(BinaryOperator)
      macro(CallInst)
        macro(IntrinsicInst)
          macro(DbgInfoIntrinsic)
            macro(DbgDeclareInst)
          macro(MemIntrinsic)
            macro(MemCpyInst)
            macro(MemMoveInst)
            macro(MemSetInst)
      macro(CmpInst)
        macro(FCmpInst)
        macro(ICmpInst)
      macro(ExtractElementInst)
      macro(GetElementPtrInst)
      macro(InsertElementInst)
      macro(InsertValueInst)
      macro(LandingPadInst)
      macro(PHINode)
      macro(SelectInst)
      macro(ShuffleVectorInst)
      macro(StoreInst)
      macro(TerminatorInst)
        macro(BranchInst)
        macro(IndirectBrInst)
        macro(InvokeInst)
        macro(ReturnInst)
        macro(SwitchInst)
        macro(UnreachableInst)
        macro(ResumeInst)
        macro(CleanupReturnInst)
        macro(CatchReturnInst)
      macro(FuncletPadInst)
        macro(CatchPadInst)
        macro(CleanupPadInst)
      macro(UnaryInstruction)
        macro(AllocaInst)
        macro(CastInst)
          macro(AddrSpaceCastInst)
          macro(BitCastInst)
          macro(FPExtInst)
          macro(FPToSIInst)
          macro(FPToUIInst)
          macro(FPTruncInst)
          macro(IntToPtrInst)
          macro(PtrToIntInst)
          macro(SExtInst)
          macro(SIToFPInst)
          macro(TruncInst)
          macro(UIToFPInst)
          macro(ZExtInst)
        macro(ExtractValueInst)
        macro(LoadInst)
        macro(VAArgInst)
*/
module llvm_hiwrap.value.value;

import llvm_hiwrap.types;

import llvm_hiwrap.type.type;

struct Value {
    LxValue value;
    alias value this;

    /** Convert to a basic block.
     *
     * The type of a basic block is label.
     *
     * TODO are all basic block labels or are basic blocks a subset?
     */
    auto asBasicBlock() {
        assert(type.kind == LxTypeKind.Label);
        import llvm : LLVMValueAsBasicBlock;
        import llvm_hiwrap.value.basic_block;

        auto raw = LLVMValueAsBasicBlock(this);
        auto v = LxBasicBlock(raw);
        return BasicBlock(v);
    }

    auto asFunction() {
        import llvm_hiwrap.value.function_;

        assert(type.kind == LxTypeKind.Function);
        return FunctionValue(this.LxUserValue.LxFunctionValue);
    }

    auto asUser() {
        import llvm_hiwrap.value.user;

        return value.LxUserValue.UserValue;
    }

    /// Uses the pointer as a unique identifier.
    size_t id() {
        return cast(size_t) value;
    }

    /// Determine whether an LLVMValueRef is itself a basic block.
    bool isBasicBlock() {
        import llvm : LLVMValueIsBasicBlock;

        return LLVMValueIsBasicBlock(this) != 0;
    }

    /// Determine whether the specified value instance is constant.
    bool isConstant() {
        import llvm : LLVMIsConstant;

        return LLVMIsConstant(rawPtr) != 0;
    }

    LxValue isMDNode() {
        import llvm : LLVMIsAMDNode;

        return LxValue(LLVMIsAMDNode(rawPtr));
    }

    /// Determine whether a value instance is undefined.
    bool isUndefined() {
        import llvm : LLVMIsUndef;

        return LLVMIsUndef(rawPtr) != 0;
    }

    /** Obtain the enumerated type of a Value instance.
     *
     * @see llvm::Value::getValueID()
     */
    LxValueKind kind() {
        import llvm : LLVMGetValueKind;

        auto k = LLVMGetValueKind(this);
        if (k >= LxValueKind.min && k <= LxValueKind.max)
            return cast(LxValueKind) k;
        return LxValueKind.Unknown;
    }

    @property const(char)[] name() {
        import std.string : fromStringz;
        import llvm : LLVMGetValueName;

        auto s = LLVMGetValueName(rawPtr);
        return s.fromStringz;
    }

    @property void name(string s) {
        import std.string : toStringz;
        import llvm : LLVMSetValueName;

        auto tmp = s.toStringz;
        LLVMSetValueName(rawPtr, tmp);
    }

    /// Obtain the string name of a value.
    LxMessage spelling() {
        import llvm : LLVMPrintValueToString;

        auto s = LLVMPrintValueToString(rawPtr);
        return LxMessage(s);
    }

    /// Returns: Inspect all uses of the value.
    auto uses() {
        import llvm_hiwrap.value.use;

        return UseValueRange(this);
    }

    /// Obtain the type of a value.
    Type type() {
        import llvm : LLVMTypeOf;

        return LLVMTypeOf(value).LxType.Type;
    }
}

struct UseValueRange {
    import std.typecons : Nullable;
    import llvm;
    import llvm_hiwrap.value.use;

    private Nullable!UseValue cur;

    this(Value v) {
        if (auto raw = LLVMGetFirstUse(v))
            cur = LLVMGetFirstUse(v).LxUseValue.UseValue;
    }

    UseValue front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return cur;
    }

    void popFront() nothrow {
        assert(!empty, "Can't pop front of an empty range");
        if (auto raw = LLVMGetNextUse(cur)) {
            cur = raw.LxUseValue.UseValue;
        } else {
            cur.nullify;
        }
    }

    bool empty() @safe pure nothrow const @nogc {
        return cur.isNull;
    }
}
