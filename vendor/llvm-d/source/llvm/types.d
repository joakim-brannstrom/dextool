module llvm.types;

public import std.stdint : uintptr_t;

import llvm.config;

/+ Analysis +/

alias int LLVMVerifierFailureAction;

/+ Transforms +/

/++ Pass manager builder ++/

struct LLVMOpaquePassManagerBuilder {}; alias LLVMOpaquePassManagerBuilder* LLVMPassManagerBuilderRef;

/+ Core +/

static if (LLVM_Version >= asVersion(3, 4, 0))
{
	alias extern(C) void function(const char* Reason) LLVMFatalErrorHandler;
}

static if (LLVM_Version >= asVersion(3, 5, 0))
{
	//This is here because putting it where it semantically belongs creates a forward reference issues.
	struct LLVMOpaqueDiagnosticInfo {}; alias LLVMOpaqueDiagnosticInfo* LLVMDiagnosticInfoRef;

	alias extern(C) void function(LLVMDiagnosticInfoRef, void*) LLVMDiagnosticHandler;
	alias extern(C) void function(LLVMContextRef, void *) LLVMYieldCallback;
}

/++ Types and Enumerations ++/

alias int LLVMBool;
struct LLVMOpaqueContext {}; alias LLVMOpaqueContext* LLVMContextRef;
struct LLVMOpaqueModule {}; alias LLVMOpaqueModule* LLVMModuleRef;
struct LLVMOpaqueType {}; alias LLVMOpaqueType* LLVMTypeRef;
struct LLVMOpaqueValue {}; alias LLVMOpaqueValue* LLVMValueRef;
struct LLVMOpaqueBasicBlock {}; alias LLVMOpaqueBasicBlock* LLVMBasicBlockRef;
struct LLVMOpaqueBuilder {}; alias LLVMOpaqueBuilder* LLVMBuilderRef;
struct LLVMOpaqueModuleProvider {}; alias LLVMOpaqueModuleProvider* LLVMModuleProviderRef;
struct LLVMOpaqueMemoryBuffer {}; alias LLVMOpaqueMemoryBuffer* LLVMMemoryBufferRef;
struct LLVMOpaquePassManager {}; alias LLVMOpaquePassManager* LLVMPassManagerRef;
struct LLVMOpaquePassRegistry {}; alias LLVMOpaquePassRegistry* LLVMPassRegistryRef;
struct LLVMOpaqueUse {}; alias LLVMOpaqueUse* LLVMUseRef;

static if (LLVM_Version >= asVersion(3, 9, 0))
{
	struct LLVMOpaqueAttributeRef {}; alias LLVMOpaqueAttributeRef* LLVMAttributeRef;
}

alias long LLVMAttribute;
alias int LLVMOpcode;
alias int LLVMTypeKind;
alias int LLVMLinkage;
alias int LLVMVisibility;
alias int LLVMDLLStorageClass;
alias int LLVMCallConv;
alias int LLVMIntPredicate;
alias int LLVMRealPredicate;
alias int LLVMLandingPadClauseTy;
static if (LLVM_Version >= asVersion(3, 3, 0))
{
	alias int LLVMThreadLocalMode;
	alias int LLVMAtomicOrdering;
	alias int LLVMAtomicRMWBinOp;
}
static if (LLVM_Version >= asVersion(3, 5, 0))
{
	alias int LLVMDiagnosticSeverity;
}
static if (LLVM_Version >= asVersion(3, 9, 0))
{
	alias int LLVMValueKind;
	alias uint LLVMAttributeIndex;
}
/+ Disassembler +/

alias void* LLVMDisasmContextRef;
alias extern(C) int function(void* DisInfo, ulong PC, ulong Offset, ulong Size, int TagType, void* TagBuf) LLVMOpInfoCallback;
alias extern(C) const char* function(void* DisInfo, ulong ReferenceValue, ulong* ReferenceType, ulong ReferencePC, const char** ReferenceName) LLVMSymbolLookupCallback;

struct LLVMOpInfoSymbol1
{
	ulong Present;
	const char* Name;
	ulong Value;
}

struct LLVMOpInfo1
{
	LLVMOpInfoSymbol1 AddSymbol;
	LLVMOpInfoSymbol1 SubtractSymbol;
	ulong Value;
	ulong VariantKind;
}

static if (LLVM_Version < asVersion(3, 3, 0))
{
	/+ Enhanced Disassembly +/

	alias void* EDDisassemblerRef;
	alias void* EDInstRef;
	alias void* EDTokenRef;
	alias void* EDOperandRef;

	alias int EDAssemblySyntax_t;

	alias extern(C) int function(ubyte* Byte, ulong address, void* arg) EDByteReaderCallback;
	alias extern(C) int function(ulong* value, uint regID, void* arg) EDRegisterReaderCallback;

	alias extern(C) int function(ubyte* Byte, ulong address) EDByteBlock_t;
	alias extern(C) int function(ulong* value, uint regID) EDRegisterBlock_t;
	alias extern(C) int function(EDTokenRef token) EDTokenVisitor_t;
}

/+ Execution Engine +/

struct LLVMOpaqueGenericValue {}; alias LLVMOpaqueGenericValue* LLVMGenericValueRef;
struct LLVMOpaqueExecutionEngine {}; alias LLVMOpaqueExecutionEngine* LLVMExecutionEngineRef;

static if (LLVM_Version >= asVersion(3, 3, 0))
{
	static if (LLVM_Version >= asVersion(3, 4, 0))
	{
		struct LLVMOpaqueMCJITMemoryManager {}; alias LLVMOpaqueMCJITMemoryManager* LLVMMCJITMemoryManagerRef;

		struct LLVMMCJITCompilerOptions
		{
			uint OptLevel;
			LLVMCodeModel CodeModel;
			LLVMBool NoFramePointerElim;
			LLVMBool EnableFastISel;
			LLVMMCJITMemoryManagerRef MCJMM;
		}

		alias extern(C) ubyte function(void* Opaque, uintptr_t Size, uint Alignment, uint SectionID, const char* SectionName) LLVMMemoryManagerAllocateCodeSectionCallback;
		alias extern(C) ubyte function(void* Opaque, uintptr_t Size, uint Alignment, uint SectionID, const char* SectionName, LLVMBool IsReadOnly) LLVMMemoryManagerAllocateDataSectionCallback;
		alias extern(C) LLVMBool function(void* Opaque, char** ErrMsg) LLVMMemoryManagerFinalizeMemoryCallback;
		alias extern(C) void function(void* Opaque) LLVMMemoryManagerDestroyCallback;
	}
	else
	{
		struct LLVMMCJITCompilerOptions
		{
			uint OptLevel;
			LLVMCodeModel CodeModel;
			LLVMBool NoFramePointerElim;
			LLVMBool EnableFastISel;
		}
	}
}

static if (LLVM_Version >= asVersion(3, 2, 0))
{
	/+ Linker +/

	alias int LLVMLinkerMode;
}

/+ Link Time Optimization +/
alias bool lto_bool_t;
alias void* llvm_lto_t;
alias llvm_lto_status llvm_lto_status_t;


alias int llvm_lto_status;

/+ LTO +/

static if (LLVM_Version >= asVersion(3, 5, 0))
{
	struct LLVMOpaqueLTOModule {}; alias LLVMOpaqueLTOModule* lto_module_t;
}
else
{
	struct LTOModule {}; alias LTOModule* lto_module_t;
}
static if (LLVM_Version >= asVersion(3, 5, 0))
{
	struct LLVMOpaqueLTOCodeGenerator {}; alias LLVMOpaqueLTOCodeGenerator* lto_code_gen_t;
}
else
{
	struct LTOCodeGenerator {}; alias LTOCodeGenerator* lto_code_gen_t;
}
static if (LLVM_Version >= asVersion(3, 9, 0))
{
	struct LLVMOpaqueThinLTOCodeGenerator {}; alias LLVMOpaqueThinLTOCodeGenerator* thinlto_code_gen_t;
}

alias int lto_symbol_attributes;
alias int lto_debug_model;
alias int lto_codegen_model;
alias int lto_codegen_diagnostic_severity_t;
alias extern(C) void function(lto_codegen_diagnostic_severity_t severity, const(char)* diag, void* ctxt) lto_diagnostic_handler_t;

/+ Object file reading and writing +/

struct LLVMOpaqueObjectFile {}; alias LLVMOpaqueObjectFile* LLVMObjectFileRef;
struct LLVMOpaqueSectionIterator {}; alias LLVMOpaqueSectionIterator* LLVMSectionIteratorRef;
struct LLVMOpaqueSymbolIterator {}; alias LLVMOpaqueSymbolIterator* LLVMSymbolIteratorRef;
struct LLVMOpaqueRelocationIterator {}; alias LLVMOpaqueRelocationIterator* LLVMRelocationIteratorRef;

/+ Target information +/

struct LLVMOpaqueTargetData {}; alias LLVMOpaqueTargetData* LLVMTargetDataRef;
struct LLVMOpaqueTargetLibraryInfotData {}; alias LLVMOpaqueTargetLibraryInfotData* LLVMTargetLibraryInfoRef;
static if (LLVM_Version < asVersion(3, 4, 0))
{
	struct LLVMStructLayout {}; alias LLVMStructLayout* LLVMStructLayoutRef;
}
alias int LLVMByteOrdering;

/+ Target machine +/

struct LLVMOpaqueTargetMachine {}; alias LLVMOpaqueTargetMachine* LLVMTargetMachineRef;
struct LLVMTarget {}; alias LLVMTarget* LLVMTargetRef;

alias int LLVMCodeGenOptLevel;
alias int LLVMRelocMode;
alias int LLVMCodeModel;
alias int LLVMCodeGenFileType;

static if (LLVM_Version >= asVersion(3, 8, 0))
{
	/+ JIT compilation of LLVM IR +/
	
	struct LLVMOrcOpaqueJITStack {}; alias LLVMOrcOpaqueJITStack* LLVMOrcJITStackRef;

	alias uint LLVMOrcModuleHandle;
	alias ulong LLVMOrcTargetAddress;

	alias extern(C) ulong function(const(char)* Name, void* LookupCtx) LLVMOrcSymbolResolverFn;
	alias extern(C) ulong function(LLVMOrcJITStackRef JITStack, void* CallbackCtx) LLVMOrcLazyCompileCallbackFn;
}

static if (LLVM_Version >= asVersion(3, 9, 0))
{
	alias int LLVMOrcErrorCode;

	struct LTOObjectBuffer
	{
		const(char)* Buffer;
		size_t Size;
	}
}