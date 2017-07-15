module samples.fibonacci;

import std.conv : to;
import std.stdio : writefln, writeln;
import std.string : toStringz, fromStringz;

import llvm;

immutable useMCJIT = {
    // MCJIT does not work on Windows
    version(Windows) { return false; }
    else {
        // Use MCJIT only if LLVMGetFunctionAddress is available,
        // as LLVMRunFunction does not work reliably with it.
        static if (LLVM_Version >= asVersion(3,6,0)) { return true; }
        else { return false; }
    }
}();

void initJIT(ref LLVMExecutionEngineRef engine, LLVMModuleRef genModule)
{
    char* error;

    static if (useMCJIT) {
        LLVMMCJITCompilerOptions options;
        LLVMInitializeMCJITCompilerOptions(&options, options.sizeof);

        LLVMCreateMCJITCompilerForModule(&engine, genModule, &options, options.sizeof, &error);
    } else {
        LLVMCreateJITCompilerForModule(&engine, genModule, 2, &error);
    }

    if (error)
    {
        scope (exit) LLVMDisposeMessage(error);
        throw new Exception(error.fromStringz().idup);
    }
}

int main(string[] args)
{
    char* error;

    LLVMInitializeNativeTarget();
    LLVMInitializeNativeAsmPrinter();
    LLVMInitializeNativeAsmParser();

    auto genModule = LLVMModuleCreateWithName("fibonacci".toStringz());
    auto genFibParams = [ LLVMInt32Type() ];
    auto genFib = LLVMAddFunction(
        genModule,
        "fib",
        LLVMFunctionType(LLVMInt32Type(), genFibParams.ptr, 1, cast(LLVMBool) false));
    LLVMSetFunctionCallConv(genFib, LLVMCCallConv);

    auto genN = LLVMGetParam(genFib, 0);

    auto genEntryBlk = LLVMAppendBasicBlock(genFib, "entry".toStringz());
    auto genAnchor0Blk = LLVMAppendBasicBlock(genFib, "anchor0".toStringz());
    auto genAnchor1Blk = LLVMAppendBasicBlock(genFib, "anchor1".toStringz());
    auto genRecurseBlk = LLVMAppendBasicBlock(genFib, "recurse".toStringz());
    auto end = LLVMAppendBasicBlock(genFib, "end".toStringz());

    auto builder = LLVMCreateBuilder();

    /+ Entry block +/
    LLVMPositionBuilderAtEnd(builder, genEntryBlk);
    auto fibSwitch = LLVMBuildSwitch(
        builder,
        genN,
        genRecurseBlk,
        2);
    LLVMAddCase(fibSwitch, LLVMConstInt(LLVMInt32Type(), 0, cast(LLVMBool) false), genAnchor0Blk);
    LLVMAddCase(fibSwitch, LLVMConstInt(LLVMInt32Type(), 1, cast(LLVMBool) false), genAnchor1Blk);

    /+ Block for n = 0: fib(n) = 0 +/
    LLVMPositionBuilderAtEnd(builder, genAnchor0Blk);
    auto genAnchor0Result = LLVMConstInt(LLVMInt32Type(), 0, cast(LLVMBool) false);
    LLVMBuildBr(builder, end);

    /+ Block for n = 1: fib(n) = 1 +/
    LLVMPositionBuilderAtEnd(builder, genAnchor1Blk);
    auto genAnchor1Result = LLVMConstInt(LLVMInt32Type(), 1, cast(LLVMBool) false);
    LLVMBuildBr(builder, end);

    /+ Block for n > 1: fib(n) = fib(n - 1) + fib(n - 2) +/
    LLVMPositionBuilderAtEnd(builder, genRecurseBlk);

    auto genNMinus1 = LLVMBuildSub(
        builder,
        genN,
        LLVMConstInt(LLVMInt32Type(), 1, cast(LLVMBool) false),
        "n - 1".toStringz());
    auto genCallFibNMinus1 = LLVMBuildCall(builder, genFib, [genNMinus1].ptr, 1, "fib(n - 1)".toStringz());

    auto genNMinus2 = LLVMBuildSub(
        builder,
        genN,
        LLVMConstInt(LLVMInt32Type(), 2, cast(LLVMBool) false),
        "n - 2".toStringz());
    auto genCallFibNMinus2 = LLVMBuildCall(builder, genFib, [genNMinus2].ptr, 1, "fib(n - 2)".toStringz());

    auto genRecurseResult = LLVMBuildAdd(builder, genCallFibNMinus1, genCallFibNMinus2, "fib(n - 1) + fib(n - 2)".toStringz());
    LLVMBuildBr(builder, end);

    /+ Block for collecting the final result +/
    LLVMPositionBuilderAtEnd(builder, end);
    auto genFinalResult = LLVMBuildPhi(builder, LLVMInt32Type(), "result".toStringz());
    auto phiValues = [ genAnchor0Result, genAnchor1Result, genRecurseResult ];
    auto phiBlocks = [ genAnchor0Blk, genAnchor1Blk, genRecurseBlk ];
    LLVMAddIncoming(genFinalResult, phiValues.ptr, phiBlocks.ptr, 3);
    LLVMBuildRet(builder, genFinalResult);

    LLVMVerifyModule(genModule, LLVMAbortProcessAction, &error);
    LLVMDisposeMessage(error);

    LLVMExecutionEngineRef engine;
    error = null;

    initJIT(engine, genModule);

    auto pass = LLVMCreatePassManager();
    static if (LLVM_Version < asVersion(3,9,0))
    {
        LLVMAddTargetData(LLVMGetExecutionEngineTargetData(engine), pass);
    }
    LLVMAddConstantPropagationPass(pass);
    LLVMAddInstructionCombiningPass(pass);
    LLVMAddPromoteMemoryToRegisterPass(pass);
    LLVMAddGVNPass(pass);
    LLVMAddCFGSimplificationPass(pass);
    LLVMRunPassManager(pass, genModule);

    writefln("The following module has been generated for the fibonacci series:\n");
    LLVMDumpModule(genModule);

    writeln();

    int n = 10;
    if (args.length > 1)
    {
        n = to!int(args[1]);
    }
    else
    {
        writefln("; Argument for fib missing on command line, using default:  \"%d\"", n);
    }

    int fib(int n)
    {
        static if (useMCJIT) {
            alias Fib = extern (C) int function(int);
            auto fib = cast(Fib) LLVMGetFunctionAddress(engine, "fib".toStringz());
            return fib(n);
        } else {
            auto args = [ LLVMCreateGenericValueOfInt(LLVMInt32Type(), n, cast(LLVMBool) 0) ];
            return LLVMGenericValueToInt(LLVMRunFunction(engine, f, 1, args.ptr), 0);
        }
    }

    writefln("; Running (jit-compiled) fib(%d)...", n);
    writefln("; fib(%d) = %d", n, fib(n));

    LLVMDisposePassManager(pass);
    LLVMDisposeBuilder(builder);
    LLVMDisposeExecutionEngine(engine);
    return 0;
}
