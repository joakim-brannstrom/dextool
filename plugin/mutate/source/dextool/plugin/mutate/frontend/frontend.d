/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.frontend.frontend;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type : AbsolutePath, FileName, ExitStatusType;

import dextool.plugin.mutate.frontend.argparser : ArgParser, ToolMode;
import dextool.plugin.mutate.type : MutationOrder, ReportKind, MutationKind,
    ReportLevel;

@safe class Frontend {
    import core.time : Duration;
    import std.typecons : Nullable;

    ExitStatusType run() {
        return runMutate(this);
    }

private:
    string[] cflags;
    string[] inputFiles;
    AbsolutePath db;
    AbsolutePath outputDirectory;
    AbsolutePath restrictDir;
    AbsolutePath mutationCompile;
    AbsolutePath mutationTester;
    Nullable!Duration mutationTesterRuntime;
    MutationKind[] mutation;
    Nullable!long mutationId;
    CompileCommandDB compileDb;
    ToolMode toolMode;
    bool dryRun;
    MutationOrder mutationOrder;
    ReportKind reportKind;
    ReportLevel reportLevel;
}

@safe:

auto buildFrontend(ref ArgParser p) {
    import core.time : dur;
    import dextool.compilation_db;

    auto r = new Frontend;

    r.cflags = p.cflags;
    r.inputFiles = p.inFiles;
    r.mutation = p.mutation;
    r.mutationId = p.mutationId;
    r.toolMode = p.toolMode;
    r.db = AbsolutePath(FileName(p.db));
    r.mutationTester = AbsolutePath(FileName(p.mutationTester));
    r.mutationCompile = AbsolutePath(FileName(p.mutationCompile));
    r.dryRun = p.dryRun;
    r.mutationOrder = p.mutationOrder;
    r.reportKind = p.reportKind;
    r.reportLevel = p.reportLevel;

    r.restrictDir = AbsolutePath(FileName(p.restrictDir));

    if (p.outputDirectory.length == 0) {
        r.outputDirectory = r.restrictDir;
    } else {
        r.outputDirectory = AbsolutePath(FileName(p.outputDirectory));
    }

    if (p.mutationTesterRuntime != 0)
        r.mutationTesterRuntime = p.mutationTesterRuntime.dur!"msecs";

    if (p.compileDb.length != 0) {
        r.compileDb = p.compileDb.fromArgCompileDb;
    }

    return r;
}

private:

ExitStatusType runMutate(Frontend fe) {
    import dextool.compilation_db : CompileCommandFilter,
        defaultCompilerFlagFilter;
    import dextool.user_filerange;
    import dextool.plugin.mutate.backend : Database;

    auto fe_io = new FrontendIO(fe.restrictDir, fe.outputDirectory, fe.dryRun);
    scope (success)
        fe_io.release;
    auto fe_validate = new FrontendValidateLoc(fe.restrictDir, fe.outputDirectory);

    auto db = Database.make(fe.db, fe.mutationOrder);

    auto default_filter = CompileCommandFilter(defaultCompilerFlagFilter, 1);
    auto frange = UserFileRange(fe.compileDb, fe.inputFiles, fe.cflags, default_filter);

    logger.trace("ToolMode: ", fe.toolMode);

    final switch (fe.toolMode) {
    case ToolMode.none:
        logger.error("No --mode specified");
        return ExitStatusType.Errors;
    case ToolMode.analyzer:
        import dextool.plugin.mutate.backend : runAnalyzer;

        return runAnalyzer(db, frange, fe_validate, fe_io);
    case ToolMode.generate_mutant:
        import dextool.plugin.mutate.backend : runGenerateMutant;

        return runGenerateMutant(db, fe.mutation, fe.mutationId, fe_io, fe_validate);
    case ToolMode.test_mutants:
        import dextool.plugin.mutate.backend : runTestMutant;

        return runTestMutant(db, fe.mutation, fe.mutationTester,
                fe.mutationCompile, fe.mutationTesterRuntime, fe_io);
    case ToolMode.report:
        import dextool.plugin.mutate.backend : runReport;

        return runReport(db, fe.mutation, fe.reportKind, fe.reportLevel, fe_io);
    }
}

import dextool.plugin.mutate.backend : FilesysIO, ValidateLoc;

/** Responsible for ensuring that when the output from the backend is written
 * to a file it is within the user specified output directory.
 *
 * When the mode dry_run is set no files shall be written to the filesystem.
 * Any kind of file shall be readable and "emulated" that it is writtable.
 *
 * Dryrun is used for testing the mutate plugin.
 *
 * #SPC-plugin_mutate_file_security-single_output
 */
final class FrontendIO : FilesysIO {
    import std.exception : collectException, Exception;
    import std.stdio : File;
    import dextool.type : AbsolutePath;
    import dextool.plugin.mutate.backend : SafeOutput, SafeInput;
    import dextool.vfs : VirtualFileSystem, VfsFile;

    VirtualFileSystem vfs;

    private AbsolutePath restrict_dir;
    private AbsolutePath output_dir;
    private bool dry_run;

    this(AbsolutePath restrict_dir, AbsolutePath output_dir, bool dry_run) {
        this.restrict_dir = restrict_dir;
        this.output_dir = output_dir;
        this.dry_run = dry_run;
    }

    void release() {
        vfs.release();
    }

    override File getDevNull() {
        return File("/dev/null", "w");
    }

    override File getStdin() {
        static import std.stdio;

        return () @trusted{ return std.stdio.stdin; }();
    }

    override AbsolutePath getOutputDir() @safe pure nothrow @nogc {
        return output_dir;
    }

    override AbsolutePath getRestrictDir() @safe pure nothrow @nogc {
        return restrict_dir;
    }

    override SafeOutput makeOutput(AbsolutePath p) @safe {
        validate(output_dir, p, dry_run);
        return SafeOutput(p, this);
    }

    override SafeInput makeInput(AbsolutePath p) @safe {
        import std.file;

        validate(restrict_dir, p, dry_run);

        auto f = vfs.open(cast(FileName) p);
        return SafeInput(f[]);
    }

    override void putFile(AbsolutePath fname, const(ubyte)[] data) @safe {
        import std.stdio : File;

        // because a SafeInput/SafeOutput could theoretically be created via
        // other means than a FilesysIO.
        // TODO fix so this validate is not needed.
        validate(output_dir, fname, dry_run);
        if (!dry_run)
            File(fname, "w").rawWrite(data);
    }

private:
    static void validate(AbsolutePath root, AbsolutePath p, bool dry_run) {
        import std.format : format;
        import std.string : startsWith;

        if (!dry_run && !(cast(string) p).startsWith((cast(string) root))) {
            throw new Exception(format("Path '%s' escaping output directory (--out) '%s'", p, root));
        }
    }
}

final class FrontendValidateLoc : ValidateLoc {
    private AbsolutePath restrict_dir;
    private AbsolutePath output_dir;

    this(AbsolutePath restrict_dir, AbsolutePath output_dir) {
        this.restrict_dir = restrict_dir;
        this.output_dir = output_dir;
    }

    override AbsolutePath getRestrictDir() nothrow {
        return this.restrict_dir;
    }

    override bool shouldAnalyze(AbsolutePath p) {
        return this.shouldAnalyze(cast(string) p);
    }

    override bool shouldAnalyze(string p) {
        import std.string : startsWith;

        return p.startsWith(restrict_dir);
    }

    override bool shouldMutate(AbsolutePath p) {
        import std.string : startsWith;

        return (cast(string) p).startsWith(output_dir);
    }
}
