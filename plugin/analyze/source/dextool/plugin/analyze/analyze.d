/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

# Threading information flow
Main thread:
    Get all the files to analyze.
    Spawn worker threads.
    Send to the worker thread the:
        - file to analyze
        - enough data to construct an analyzer collection
    Collect the received analyze data from worker threads.
    Wait until all files are analyzed and the last worker thread has sent back the data.
    Dump the result according to the users config via CLI.

Worker thread:
    Connect a clang AST visitor with an analyzer constructed from the builder the main thread sent over.
    Run the analyze pass.
    Send back the analyze result to the main thread.

# Design Assumptions
 - No actual speed is gained if the working threads are higher than the core count.
    Thus the number of workers are <= CPU count.
 - The main thread that receive the data completely empty its mailbox.
    This is not interleaved with spawning new workers.
    This behavior will make it so that the worker threads sending data to the
    main thread reach an equilibrium.
    The number of worker threads are limited by the amount of data that the
    main thread can receive.
*/
module dextool.plugin.analyze.analyze;

import logger = std.experimental.logger;
import std.algorithm : map, filter;
import std.array : array, empty;
import std.concurrency : Tid;
import std.typecons : Flag;
import std.range : enumerate, popFront, front;

import dextool.compilation_db : limitOrAllRange, parse, prependFlags, addCompiler, replaceCompiler,
    addSystemIncludes, fileRange, ParsedCompileCommand, CompileCommandDB, Compiler;
import dextool.type : ExitStatusType, Path, AbsolutePath;

import dextool.plugin.analyze.visitor : TUVisitor;
import dextool.plugin.analyze.mccabe;

/// The commands have a lifetime that persist throughout the whole analyze thus
/// just reuse them as-is.
immutable(ParsedCompileCommand) immReuse(ParsedCompileCommand v) @trusted {
    return cast(immutable) v;
}

ExitStatusType doAnalyze(AnalyzeBuilder analyze_builder, ref AnalyzeResults analyze_results, string[] in_cflags,
        string[] in_files, CompileCommandDB compile_db, AbsolutePath restrictDir, int workerThreads) @safe {
    import std.conv : to;
    import dextool.compilation_db : defaultCompilerFilter;
    import dextool.utility : prependDefaultFlags, PreferLang;

    {
        import std.concurrency : setMaxMailboxSize, OnCrowding, thisTid;

        // safe in newer versions than 2.071.1
        () @trusted { setMaxMailboxSize(thisTid, 1024, OnCrowding.block); }();
    }

    auto compDbRange() {
        if (compile_db.empty) {
            return fileRange(in_files.map!(a => Path(a)).array, Compiler("/usr/bin/c++"));
        }
        return compile_db.fileRange;
    }

    auto files = compDbRange.parse(defaultCompilerFilter).addSystemIncludes.prependFlags(
            prependDefaultFlags(in_cflags, PreferLang.cpp)).enumerate.array;
    const total_files = files.length;

    enum State {
        none,
        init,
        putFile,
        receive,
        testFinish,
        finish,
        exit
    }

    auto pool = new Pool(workerThreads);
    State st;
    debug State old;

    while (st != State.exit) {
        debug if (st != old) {
            logger.trace("doAnalyze: ", st.to!string());
            old = st;
        }

        final switch (st) {
        case State.none:
            st = State.init;
            break;
        case State.init:
            st = State.testFinish;
            break;
        case State.putFile:
            st = State.receive;
            break;
        case State.receive:
            st = State.testFinish;
            break;
        case State.testFinish:
            if (files.empty)
                st = State.finish;
            else
                st = State.putFile;
            break;
        case State.finish:
            assert(files.empty);
            if (pool.empty)
                st = State.exit;
            break;
        case State.exit:
            break;
        }

        switch (st) {
        case State.init:
            for (; !files.empty; files.popFront) {
                if (!pool.run(&analyzeWorker, analyze_builder, files.front.index,
                        total_files, files.front.value.immReuse, restrictDir)) {
                    // reached CPU limit
                    break;
                }
            }
            break;
        case State.putFile:
            if (pool.run(&analyzeWorker, analyze_builder,
                    files.front.index, total_files, files.front.value.immReuse, restrictDir)) {
                // successfully spawned a worker
                files.popFront;
            }
            break;
        case State.receive:
            goto case;
        case State.finish:
            pool.receive((dextool.plugin.analyze.mccabe.Function a) {
                analyze_results.put(a);
            });
            break;
        default:
            break;
        }
    }

    return ExitStatusType.Ok;
}

void analyzeWorker(Tid owner, AnalyzeBuilder analyze_builder, size_t file_idx,
        size_t total_files, immutable ParsedCompileCommand pdata, AbsolutePath restrictDir) nothrow {
    import std.concurrency : send;
    import std.typecons : Yes;
    import std.exception : collectException;
    import dextool.utility : analyzeFile;
    import libclang_ast.context : ClangContext;

    try {
        logger.infof("File %d/%d ", file_idx + 1, total_files);
    } catch (Exception e) {
    }

    auto visitor = new TUVisitor(restrictDir);
    AnalyzeCollection analyzers;
    try {
        analyzers = analyze_builder.finalize;
        analyzers.register(visitor);
        auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        if (analyzeFile(pdata.cmd.absoluteFile, pdata.flags.completeFlags,
                visitor, ctx) == ExitStatusType.Errors) {
            logger.error("Unable to analyze: ", cast(string) pdata.cmd.absoluteFile);
            return;
        }
    } catch (Exception e) {
        collectException(logger.error(e.msg));
    }

    foreach (f; analyzers.mcCabeResult.functions[]) {
        try {
            // assuming send is correctly implemented.
            () @trusted { owner.send(f); }();
        } catch (Exception e) {
            collectException(logger.error("Unable to send to owner thread '%s': %s", owner, e.msg));
        }
    }
}

class Pool {
    import std.concurrency : Tid, thisTid;
    import std.typecons : Nullable;

    Tid[] pool;
    int workerThreads;

    this(int workerThreads) @safe {
        import std.parallelism : totalCPUs;

        if (workerThreads <= 0) {
            this.workerThreads = totalCPUs;
        } else {
            this.workerThreads = workerThreads;
        }
    }

    bool run(F, ARGS...)(F func, auto ref ARGS args) {
        auto tid = makeWorker(func, args);
        return !tid.isNull;
    }

    /** Relay data in the mailbox back to the provided function.
     *
     * trusted: on the assumption that receiveTimeout is @safe _enough_.
     * assuming `ops` is @safe.
     *
     * Returns: if data where received
     */
    bool receive(T)(T ops) @trusted {
        import core.time;
        import std.concurrency : LinkTerminated, receiveTimeout;

        bool got_any_data;

        try {
            // empty the mailbox of data
            for (;;) {
                auto got_data = receiveTimeout(msecs(0), ops);
                got_any_data = got_any_data || got_data;

                if (!got_data) {
                    break;
                }
            }
        } catch (LinkTerminated e) {
            removeWorker(e.tid);
        }

        return got_any_data;
    }

    bool empty() @safe {
        return pool.length == 0;
    }

    void removeWorker(Tid tid) {
        import std.array : array;

        pool = pool.filter!(a => tid != a).array();
    }

    //TODO add attribute check of func so only @safe func can be used.
    Nullable!Tid makeWorker(F, ARGS...)(F func, auto ref ARGS args) {
        import std.concurrency : spawnLinked;

        typeof(return) rval;

        if (pool.length < workerThreads) {
            // assuming that spawnLinked is of high quality. Assuming func is @safe.
            rval = () @trusted { return spawnLinked(func, thisTid, args); }();
            pool ~= rval.get;
        }

        return rval;
    }
}

/** Hold the configuration parameters used to construct analyze collections.
 *
 * It is intended to be used to construct analyze collections in the worker
 * threads.
 *
 * It is important that the member variables can be passed to a thread.
 * This is easiest if they are of primitive types.
 */
struct AnalyzeBuilder {
    private {
        Flag!"doMcCabeAnalyze" analyzeMcCabe;
    }

    static auto make() {
        return AnalyzeBuilder();
    }

    auto mcCabe(bool do_this_analyze) {
        analyzeMcCabe = cast(Flag!"doMcCabeAnalyze") do_this_analyze;
        return this;
    }

    auto finalize() {
        return AnalyzeCollection(analyzeMcCabe);
    }
}

/** Analyzers used in worker threads to collect results.
 *
 * TODO reduce null checks. It is a sign of weakness in the design.
 */
struct AnalyzeCollection {
    import libclang_ast.ast.declaration;

    McCabeResult mcCabeResult;
    private McCabe mcCabe;
    private bool doMcCabe;

    this(Flag!"doMcCabeAnalyze" mccabe) {
        doMcCabe = mccabe;
        this.mcCabeResult = new McCabeResult;
        this.mcCabe = new McCabe(mcCabeResult);
    }

    void register(TUVisitor v) @trusted {
        if (doMcCabe) {
            v.onFunctionDecl ~= &mcCabe.analyze!FunctionDecl;
            v.onCXXMethod ~= &mcCabe.analyze!CXXMethod;
            v.onConstructor ~= &mcCabe.analyze!Constructor;
            v.onDestructor ~= &mcCabe.analyze!Destructor;
            v.onConversionFunction ~= &mcCabe.analyze!ConversionFunction;
            v.onFunctionTemplate ~= &mcCabe.analyze!FunctionTemplate;
        }
    }
}

/** Results collected in the main thread.
 */
struct AnalyzeResults {
    private {
        AbsolutePath outdir;

        McCabeResult mcCabe;
        int mccabeThreshold;
        Flag!"dumpMcCabe" dumpMcCabe;

        Flag!"outputJson" json_;
        Flag!"outputStdout" stdout_;
    }

    static auto make() {
        return Builder();
    }

    struct Builder {
        private AbsolutePath outdir;
        private bool dumpMcCabe;
        private int mccabeThreshold;
        private bool json_;
        private bool stdout_;

        auto mcCabe(bool dump_this, int threshold) {
            this.dumpMcCabe = dump_this;
            this.mccabeThreshold = threshold;
            return this;
        }

        auto json(bool v) {
            this.json_ = v;
            return this;
        }

        auto stdout(bool v) {
            this.stdout_ = v;
            return this;
        }

        auto outputDirectory(string path) {
            this.outdir = AbsolutePath(Path(path));
            return this;
        }

        auto finalize() {
            // dfmt off
            return AnalyzeResults(outdir,
                                  new McCabeResult,
                                  mccabeThreshold,
                                  cast(Flag!"dumpMcCabe") dumpMcCabe,
                                  cast(Flag!"outputJson") json_,
                                  cast(Flag!"outputStdout") stdout_,
                                  );
            // dfmt on
        }
    }

    void put(dextool.plugin.analyze.mccabe.Function f) @safe {
        mcCabe.put(f);
    }

    void dumpResult() @safe {
        import std.path : buildPath;

        const string base = buildPath(outdir, "result_");

        if (dumpMcCabe) {
            if (json_)
                dextool.plugin.analyze.mccabe.resultToJson(Path(base ~ "mccabe.json")
                        .AbsolutePath, mcCabe, mccabeThreshold);
            if (stdout_)
                dextool.plugin.analyze.mccabe.resultToStdout(mcCabe, mccabeThreshold);
        }
    }
}
