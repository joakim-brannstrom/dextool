/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

partof: #SPC-llvm_hiwrap_module_error_handling
Diagnostic messages are part of the created module result to make it easy for
the user to find those specific messages created during the module creation.
*/
module llvm_hiwrap.context;

import llvm;

struct Context {
    import llvm_hiwrap.buffer : MemoryBuffer;
    import llvm_hiwrap.module_;
    import llvm_hiwrap.value.metadata;

    LLVMContextRef lx;
    alias lx this;

    /// Collected diagnostic messages during usage.
    DiagnosticSet diagnostic;

    /// Make an empty LLVM context.
    static auto make() {
        return Context(LLVMContextCreate);
    }

    @disable this();
    @disable this(this);

    /** Wrap an existing context and thus providing deterministic resource
     * handling.
     */
    this(LLVMContextRef lx) {
        this.lx = lx;
        LLVMContextSetDiagnosticHandler(lx,
                &DiagnosticSet.dextoolLLVM_HandleDiagnostic, cast(void*)&diagnostic);
    }

    ~this() {
        LLVMContextDispose(lx);
    }

    /** Create a new, empty module in a specific context.
     */
    Module makeModule(string id) {
        import std.string : toStringz;

        auto s = id.toStringz;
        return Module(LLVMModuleCreateWithNameInContext(s, lx));
    }

    /** Make a `Module` from the specified `MemoryBuffer`.
     *
     * Assumtion: the memory buffer is only needed to create the module. It do
     * not have to be kept alive after the function has finished. This is in
     * contrast with the lazy API which would need to keep both alive.
     *
     * The ModuleID is derived from `buffer`.
     *
     * Diagnostic messages that are created by this operation become part of
     * the result.
     */
    ModuleFromMemoryBufferResult makeModule(ref MemoryBuffer buffer) {
        LLVMModuleRef m;
        LLVMBool success;

        size_t curr_dia_idx = diagnostic.length;
        if (curr_dia_idx != 0)
            curr_dia_idx -= 1;

        static if (LLVM_Version >= asVersion(3, 8, 0)) {
            success = LLVMParseBitcodeInContext2(lx, buffer.lx, &m);
        } else static if (LLVM_Version < asVersion(3, 9, 0)) {
            // this is deprecated.
            // prefering the new one because it provides a `LxDiagnosticSeverity`.
            LxMessage msg;
            success = LLVMParseBitcodeInContext(lx, buffer.lx, &m, &msg.rawPtr);
            if (success != 0) {
                // the severity is unknown therefor be extra causes by always
                // assuming the worst.
                diagnostic ~= Diagnostic(LxDiagnosticSeverity.LLVMDSError, msg.toD);
            }
        } else {
            static assert(0, "should never happen");
        }

        Diagnostic[] msgs;
        if (curr_dia_idx < diagnostic.length) {
            msgs = diagnostic[curr_dia_idx .. $];
            diagnostic = diagnostic[0 .. curr_dia_idx + 1];
        }

        // Success is funky. _false_ mean that there are no errors.
        // From the documentation llvm-c/BitReader.h:
        // Returns 0 on success.
        return ModuleFromMemoryBufferResult(Module(m), success == 0, msgs);
    }

    /** Obtain a MDString value.
     *
     * The returned instance corresponds to the llvm::MDString class.
     */
    MetadataStringValue metadataString(string name) {
        import llvm_hiwrap.types;

        return LLVMMDStringInContext(lx, cast(const(char)*) name.ptr, cast(uint) name.length)
            .LxValue.LxMetadataStringValue.MetadataStringValue;
    }

    /** Resolve the referenced nodes a NamedMetadata consist of.
     *
     * The returned value corresponds to the llvm::MDNode class which has
     * operands.
     */
    ResolvedNamedMetadataValue resolveNamedMetadata(ref NamedMetadataValue nmd) {
        import std.array : array;
        import std.algorithm : map;
        import llvm_hiwrap.types;

        //TODO refactor to remove this GC use.
        LLVMValueRef[] ops = nmd.map!(a => a.rawPtr).array();
        auto raw = LLVMMDNodeInContext(lx, ops.ptr, cast(uint) ops.length);
        return raw.LxValue.LxMetadataNodeValue.LxResolvedNamedMetadataValue
            .ResolvedNamedMetadataValue;
    }
}

struct Diagnostic {
    import std.conv : to;
    import llvm_hiwrap.types : LxMessage, LxDiagnosticSeverity;
    import llvm_hiwrap.util : toD;

    this(LLVMDiagnosticInfoRef di) {
        auto m = LxMessage(LLVMGetDiagInfoDescription(di));
        msg = m.toD;
        auto raw_severity = LLVMGetDiagInfoSeverity(di);
        severity = raw_severity.to!LxDiagnosticSeverity;
    }

    LxDiagnosticSeverity severity;
    string msg;
}

struct DiagnosticSet {
    Diagnostic[] value;
    alias value this;

    extern (C) static void dextoolLLVM_HandleDiagnostic(LLVMDiagnosticInfoRef info, void* ctx) {
        auto set = cast(DiagnosticSet*) ctx;
        set.value ~= Diagnostic(info);
    }
}

private:

struct ModuleFromMemoryBufferResult {
    import llvm_hiwrap.module_;

    private Module value_;

    /// When this is false there may exist diagnostic messages.
    bool isValid;
    Diagnostic[] diagnostic;

    @disable this(this);

    auto value() {
        assert(isValid);
        auto lx = value_.lx;
        value_.lx = null;
        return Module(lx);
    }
}
