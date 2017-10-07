/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.constant;

import llvm_hiwrap.types;

struct ConstantValue {
    import llvm;

    LxConstantValue value;
    alias value this;

    /**
     * This section contains APIs for interacting with LLVMValueRef that
     * correspond to llvm::Constant instances.
     *
     * These functions will work for any LLVMValueRef in the llvm::Constant
     * class hierarchy.
     *
     * @{
     */

    /**
     * Obtain a constant value referring to the null instance of a type.
     *
     * @see llvm::Constant::getNullValue()
     */
    //LLVMValueRef LLVMConstNull(LLVMTypeRef Ty); /* all zeroes */

    /**
     * Obtain a constant value referring to the instance of a type
     * consisting of all ones.
     *
     * This is only valid for integer types.
     *
     * @see llvm::Constant::getAllOnesValue()
     */
    //LLVMValueRef LLVMConstAllOnes(LLVMTypeRef Ty);

    /**
     * Obtain a constant value referring to an undefined value of a type.
     *
     * @see llvm::UndefValue::get()
     */
    //LLVMValueRef LLVMGetUndef(LLVMTypeRef Ty);

    /**
     * Determine whether a value instance is null.
     *
     * @see llvm::Constant::isNullValue()
     */
    //LLVMBool LLVMIsNull(LLVMValueRef Val);

    /**
     * Obtain a constant that is a constant pointer pointing to NULL for a
     * specified type.
     */
    //LLVMValueRef LLVMConstPointerNull(LLVMTypeRef Ty);
}

struct ScalarConstantValue {
    import llvm;

    LxScalarConstantValue value;
    alias value this;

    /**
     * @defgroup LLVMCCoreValueConstantScalar Scalar constants
     *
     * Functions in this group model LLVMValueRef instances that correspond
     * to constants referring to scalar types.
     *
     * For integer types, the LLVMTypeRef parameter should correspond to a
     * llvm::IntegerType instance and the returned LLVMValueRef will
     * correspond to a llvm::ConstantInt.
     *
     * For floating point types, the LLVMTypeRef returned corresponds to a
     * llvm::ConstantFP.
     *
     * @{
     */

    /**
     * Obtain a constant value for an integer type.
     *
     * The returned value corresponds to a llvm::ConstantInt.
     *
     * @see llvm::ConstantInt::get()
     *
     * @param IntTy Integer type to obtain value of.
     * @param N The value the returned instance should refer to.
     * @param SignExtend Whether to sign extend the produced value.
     */
    //LLVMValueRef LLVMConstInt(LLVMTypeRef IntTy, unsigned long long N,
    //LLVMBool SignExtend);

    /**
     * Obtain a constant value for an integer of arbitrary precision.
     *
     * @see llvm::ConstantInt::get()
     */
    //LLVMValueRef LLVMConstIntOfArbitraryPrecision(LLVMTypeRef IntTy,
    //unsigned NumWords,
    //const uint64_t Words[]);

    /**
     * Obtain a constant value for an integer parsed from a string.
     *
     * A similar API, LLVMConstIntOfStringAndSize is also available. If the
     * string's length is available, it is preferred to call that function
     * instead.
     *
     * @see llvm::ConstantInt::get()
     */
    //LLVMValueRef LLVMConstIntOfString(LLVMTypeRef IntTy, const char *Text,
    //                                  uint8_t Radix);

    /**
     * Obtain a constant value for an integer parsed from a string with
     * specified length.
     *
     * @see llvm::ConstantInt::get()
     */
    //LLVMValueRef LLVMConstIntOfStringAndSize(LLVMTypeRef IntTy, const char *Text,
    //unsigned SLen, uint8_t Radix);

    /**
     * Obtain a constant value referring to a double floating point value.
     */
    //LLVMValueRef LLVMConstReal(LLVMTypeRef RealTy, double N);

    /**
     * Obtain a constant for a floating point value parsed from a string.
     *
     * A similar API, LLVMConstRealOfStringAndSize is also available. It
     * should be used if the input string's length is known.
     */
    //LLVMValueRef LLVMConstRealOfString(LLVMTypeRef RealTy, const char *Text);

    /**
     * Obtain a constant for a floating point value parsed from a string.
     */
    //LLVMValueRef LLVMConstRealOfStringAndSize(LLVMTypeRef RealTy, const char *Text,
    //unsigned SLen);

    /**
     * Obtain the zero extended value for an integer constant value.
     *
     * @see llvm::ConstantInt::getZExtValue()
     */
    //unsigned long long LLVMConstIntGetZExtValue(LLVMValueRef ConstantVal);

    /**
     * Obtain the sign extended value for an integer constant value.
     *
     * @see llvm::ConstantInt::getSExtValue()
     */
    //long long LLVMConstIntGetSExtValue(LLVMValueRef ConstantVal);

    /**
     * Obtain the double value for an floating point constant value.
     * losesInfo indicates if some precision was lost in the conversion.
     *
     * @see llvm::ConstantFP::getDoubleValue
     */
    //double LLVMConstRealGetDouble(LLVMValueRef ConstantVal, LLVMBool *losesInfo);
}

struct CompositeConstantValue {
    LxCompositeConstantValue value;
    alias value this;

    /**
     * @defgroup LLVMCCoreValueConstantComposite Composite Constants
     *
     * Functions in this group operate on composite constants.
     *
     * @{
     */

    /**
     * Create a ConstantDataSequential and initialize it with a string.
     *
     * @see llvm::ConstantDataArray::getString()
     */
    //LLVMValueRef LLVMConstStringInContext(LLVMContextRef C, const char *Str,
    //                                      unsigned Length, LLVMBool DontNullTerminate);

    /**
     * Create a ConstantDataSequential with string content in the global context.
     *
     * This is the same as LLVMConstStringInContext except it operates on the
     * global context.
     *
     * @see LLVMConstStringInContext()
     * @see llvm::ConstantDataArray::getString()
     */
    //LLVMValueRef LLVMConstString(const char *Str, unsigned Length,
    //                             LLVMBool DontNullTerminate);

    /**
     * Returns true if the specified constant is an array of i8.
     *
     * @see ConstantDataSequential::getAsString()
     */
    //LLVMBool LLVMIsConstantString(LLVMValueRef c);

    /**
     * Get the given constant data sequential as a string.
     *
     * @see ConstantDataSequential::getAsString()
     */
    //const char *LLVMGetAsString(LLVMValueRef c, size_t *Length);

    /**
     * Create an anonymous ConstantStruct with the specified values.
     *
     * @see llvm::ConstantStruct::getAnon()
     */
    //LLVMValueRef LLVMConstStructInContext(LLVMContextRef C,
    //                                      LLVMValueRef *ConstantVals,
    //                                      unsigned Count, LLVMBool Packed);

    /**
     * Create a ConstantStruct in the global Context.
     *
     * This is the same as LLVMConstStructInContext except it operates on the
     * global Context.
     *
     * @see LLVMConstStructInContext()
     */
    //LLVMValueRef LLVMConstStruct(LLVMValueRef *ConstantVals, unsigned Count,
    //                             LLVMBool Packed);

    /**
     * Create a ConstantArray from values.
     *
     * @see llvm::ConstantArray::get()
     */
    //LLVMValueRef LLVMConstArray(LLVMTypeRef ElementTy,
    //                            LLVMValueRef *ConstantVals, unsigned Length);

    /**
     * Create a non-anonymous ConstantStruct from values.
     *
     * @see llvm::ConstantStruct::get()
     */
    //LLVMValueRef LLVMConstNamedStruct(LLVMTypeRef StructTy,
    //                                  LLVMValueRef *ConstantVals,
    //                                  unsigned Count);

    /**
     * Get an element at specified index as a constant.
     *
     * @see ConstantDataSequential::getElementAsConstant()
     */
    //LLVMValueRef LLVMGetElementAsConstant(LLVMValueRef C, unsigned idx);

    /**
     * Create a ConstantVector from values.
     *
     * @see llvm::ConstantVector::get()
     */
    //LLVMValueRef LLVMConstVector(LLVMValueRef *ScalarConstantVals, unsigned Size);
}

struct LxConstantExpressionValue {
    /**
     * @defgroup LLVMCCoreValueConstantExpressions Constant Expressions
     *
     * Functions in this group correspond to APIs on llvm::ConstantExpr.
     *
     * @see llvm::ConstantExpr.
     *
     * @{
     */
    //LLVMOpcode LLVMGetConstOpcode(LLVMValueRef ConstantVal);
    //LLVMValueRef LLVMAlignOf(LLVMTypeRef Ty);
    //LLVMValueRef LLVMSizeOf(LLVMTypeRef Ty);
    //LLVMValueRef LLVMConstNeg(LLVMValueRef ConstantVal);
    //LLVMValueRef LLVMConstNSWNeg(LLVMValueRef ConstantVal);
    //LLVMValueRef LLVMConstNUWNeg(LLVMValueRef ConstantVal);
    //LLVMValueRef LLVMConstFNeg(LLVMValueRef ConstantVal);
    //LLVMValueRef LLVMConstNot(LLVMValueRef ConstantVal);
    //LLVMValueRef LLVMConstAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstNSWAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstNUWAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstFAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstNSWSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstNUWSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstFSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstNSWMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstNUWMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstFMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstUDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstExactUDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstSDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstExactSDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstFDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstURem(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstSRem(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstFRem(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstAnd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstOr(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstXor(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstICmp(LLVMIntPredicate Predicate,
    //                           LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstFCmp(LLVMRealPredicate Predicate,
    //                           LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstShl(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstLShr(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstAShr(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
    //LLVMValueRef LLVMConstGEP(LLVMValueRef ConstantVal,
    //                          LLVMValueRef *ConstantIndices, unsigned NumIndices);
    //LLVMValueRef LLVMConstInBoundsGEP(LLVMValueRef ConstantVal,
    //                                  LLVMValueRef *ConstantIndices,
    //                                  unsigned NumIndices);
    //LLVMValueRef LLVMConstTrunc(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstSExt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstZExt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstFPTrunc(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstFPExt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstUIToFP(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstSIToFP(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstFPToUI(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstFPToSI(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstPtrToInt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstIntToPtr(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstBitCast(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstAddrSpaceCast(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstZExtOrBitCast(LLVMValueRef ConstantVal,
    //                                    LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstSExtOrBitCast(LLVMValueRef ConstantVal,
    //                                    LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstTruncOrBitCast(LLVMValueRef ConstantVal,
    //                                     LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstPointerCast(LLVMValueRef ConstantVal,
    //                                  LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstIntCast(LLVMValueRef ConstantVal, LLVMTypeRef ToType,
    //                              LLVMBool isSigned);
    //LLVMValueRef LLVMConstFPCast(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
    //LLVMValueRef LLVMConstSelect(LLVMValueRef ConstantCondition,
    //                             LLVMValueRef ConstantIfTrue,
    //                             LLVMValueRef ConstantIfFalse);
    //LLVMValueRef LLVMConstExtractElement(LLVMValueRef VectorConstant,
    //                                     LLVMValueRef IndexConstant);
    //LLVMValueRef LLVMConstInsertElement(LLVMValueRef VectorConstant,
    //                                    LLVMValueRef ElementValueConstant,
    //                                    LLVMValueRef IndexConstant);
    //LLVMValueRef LLVMConstShuffleVector(LLVMValueRef VectorAConstant,
    //                                    LLVMValueRef VectorBConstant,
    //                                    LLVMValueRef MaskConstant);
    //LLVMValueRef LLVMConstExtractValue(LLVMValueRef AggConstant, unsigned *IdxList,
    //                                   unsigned NumIdx);
    //LLVMValueRef LLVMConstInsertValue(LLVMValueRef AggConstant,
    //                                  LLVMValueRef ElementValueConstant,
    //                                  unsigned *IdxList, unsigned NumIdx);
    //LLVMValueRef LLVMConstInlineAsm(LLVMTypeRef Ty,
    //                                const char *AsmString, const char *Constraints,
    //                                LLVMBool HasSideEffects, LLVMBool IsAlignStack);
    //LLVMValueRef LLVMBlockAddress(LLVMValueRef F, LLVMBasicBlockRef BB);
}
