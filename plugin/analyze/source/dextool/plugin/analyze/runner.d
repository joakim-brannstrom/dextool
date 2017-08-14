/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.runner;

import std.stdio : writeln;
import std.typecons : Flag;
import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.plugin.analyze.visitor : TUVisitor;
import dextool.type : ExitStatusType, FileName, AbsolutePath;

import dextool.plugin.analyze.mccabe;

ExitStatusType runPlugin(string[] args) {
    import std.stdio : writeln, writefln;
    import dextool.plugin.analyze.raw_config;

    RawConfiguration pargs;
    pargs.parse(args);

    // the dextool plugin architecture requires that two lines are printed upon
    // request by the main function.
    //  - a name of the plugin.
    //  - a oneliner description.
    if (pargs.shortPluginHelp) {
        writeln("analyze");
        writeln("static code analysis of c/c++ source code");
        return ExitStatusType.Ok;
    } else if (pargs.errorHelp) {
        pargs.printHelp;
        return ExitStatusType.Errors;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    }

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    McCabe mccabe;
    if (pargs.mccabe) {
        mccabe = new McCabe(pargs.mccabeThreshold);
    }

    auto analyzers = new AnalyzeCollection(mccabe);
    doAnalyze(analyzers, pargs.cflags, pargs.files, compile_db,
            AbsolutePath(FileName(pargs.restrictDir)));

    analyzers.dumpResult(AbsolutePath(FileName(pargs.outdir)),
            cast(Flag!"json") pargs.outputJson, cast(Flag!"stdout") pargs.outputStdout);

    return ExitStatusType.Ok;
}

ExitStatusType doAnalyze(ref AnalyzeCollection analyzers, string[] in_cflags,
        string[] in_files, CompileCommandDB compile_db, AbsolutePath restrictDir) {
    import std.range : enumerate;
    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.clang : findFlags, ParseData = SearchResult;
    import dextool.utility : prependDefaultFlags, PreferLang, analyzeFile;

    const auto user_cflags = prependDefaultFlags(in_cflags, PreferLang.cpp);

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto visitor = new TUVisitor(restrictDir);
    analyzers.registerAnalyzers(visitor);

    auto files = AnalyzeFileRange(compile_db, in_files, in_cflags, defaultCompilerFilter);
    const total_files = files.length;

    foreach (idx, pdata; files.enumerate) {
        logger.infof("File %d/%d ", idx + 1, total_files);

        if (pdata.isNull) {
            logger.warning(
                    "Skipping file because it is not possible to determine the compiler flags");
            continue;
        }

        if (analyzeFile(pdata.absoluteFile, pdata.cflags, visitor, ctx) == ExitStatusType.Errors) {
            logger.error("Unable to analyze: ", cast(string) pdata.absoluteFile);
        }
    }

    return ExitStatusType.Ok;
}

class AnalyzeCollection {
    import cpptooling.analyzer.clang.ast.declaration;

    McCabe mcCabe;

    this(McCabe mccabe) {
        mcCabe = mccabe;
    }

    void registerAnalyzers(TUVisitor v) {
        if (mcCabe !is null) {
            v.onFunctionDecl ~= &mcCabe.analyze!FunctionDecl;
            v.onCXXMethod ~= &mcCabe.analyze!CXXMethod;
            v.onConstructor ~= &mcCabe.analyze!Constructor;
            v.onDestructor ~= &mcCabe.analyze!Destructor;
            v.onConversionFunction ~= &mcCabe.analyze!ConversionFunction;
            v.onFunctionTemplate ~= &mcCabe.analyze!FunctionTemplate;
        }
    }

    void dumpResult(AbsolutePath outdir, Flag!"json" json_, Flag!"stdout" stdout_) {
        import std.path : buildPath;

        const string base = buildPath(outdir, "result_");

        if (mcCabe !is null) {
            if (json_)
                dextool.plugin.analyze.mccabe.resultToJson(FileName(base ~ "mccabe.json")
                        .AbsolutePath, mcCabe);
            if (stdout_)
                dextool.plugin.analyze.mccabe.resultToStdout(mcCabe);
        }
    }
}

struct AnalyzeFileRange {
    import std.typecons : Nullable;
    import dextool.clang : findFlags;
    import dextool.compilation_db : SearchResult;

    enum RangeOver {
        inFiles,
        database
    }

    this(CompileCommandDB db, string[] in_files, string[] cflags,
            const CompileCommandFilter ccFilter) {
        this.db = db;
        this.cflags = cflags;
        this.ccFilter = ccFilter;
        this.inFiles = in_files;

        if (in_files.length == 0) {
            kind = RangeOver.database;
        } else {
            kind = RangeOver.inFiles;
        }
    }

    const RangeOver kind;
    CompileCommandDB db;
    string[] inFiles;
    string[] cflags;
    const CompileCommandFilter ccFilter;

    Nullable!SearchResult front() {
        assert(!empty, "Can't get front of an empty range");

        Nullable!SearchResult curr;

        final switch (kind) {
        case RangeOver.inFiles:
            if (db.length > 0) {
                curr = db.findFlags(FileName(inFiles[0]), cflags, ccFilter);
            } else {
                curr = SearchResult(cflags.dup, AbsolutePath(FileName(inFiles[0])));
            }
            break;
        case RangeOver.database:
            auto tmp = db.payload[0];
            curr = SearchResult(cflags ~ tmp.parseFlag(ccFilter), tmp.absoluteFile);
            break;
        }

        return curr;
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");

        final switch (kind) {
        case RangeOver.inFiles:
            inFiles = inFiles[1 .. $];
            break;
        case RangeOver.database:
            db.payload = db.payload[1 .. $];
            break;
        }
    }

    bool empty() @safe pure nothrow const @nogc {
        final switch (kind) {
        case RangeOver.inFiles:
            return inFiles.length == 0;
        case RangeOver.database:
            return db.length == 0;
        }
    }

    size_t length() @safe pure nothrow const @nogc {
        final switch (kind) {
        case RangeOver.inFiles:
            return inFiles.length;
        case RangeOver.database:
            return db.length;
        }
    }
}
