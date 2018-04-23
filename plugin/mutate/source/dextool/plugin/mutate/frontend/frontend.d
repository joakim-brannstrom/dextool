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

import dextool.plugin.mutate.frontend.argparser : ArgParser, ToolMode, Mutation;
import dextool.plugin.mutate.type : MutationOrder, ReportKind, MutationKind,
    ReportLevel, AdminOperation;

@safe class Frontend {
    import core.time : Duration;
    import std.typecons : Nullable;

    ExitStatusType run() {
        return runMutate(this);
    }

private:
    ArgParser.Data rawUserData;

    AbsolutePath db;
    AbsolutePath outputDirectory;
    AbsolutePath[] restrictDir;
    AbsolutePath mutationCompile;
    AbsolutePath mutationTester;
    AbsolutePath mutationTestCaseAnalyze;
    Nullable!Duration mutationTesterRuntime;
    CompileCommandDB compileDb;
}

@safe:

auto buildFrontend(ref ArgParser p) {
    import std.algorithm : map;
    import std.array : array;
    import core.time : dur;
    import dextool.compilation_db;

    auto r = new Frontend;

    r.rawUserData = p.data;

    r.db = AbsolutePath(FileName(p.db));
    r.mutationTester = AbsolutePath(FileName(p.mutationTester));
    r.mutationCompile = AbsolutePath(FileName(p.mutationCompile));
    if (p.mutationTestCaseAnalyze.length != 0)
        r.mutationTestCaseAnalyze = AbsolutePath(FileName(p.mutationTestCaseAnalyze));

    r.outputDirectory = AbsolutePath(FileName(p.outputDirectory.toRealPath));
    if (p.restrictDir.length == 0)
        r.restrictDir = [r.outputDirectory];
    else
        r.restrictDir = p.restrictDir.map!(a => AbsolutePath(FileName(a.toRealPath))).array;

    if (p.mutationTesterRuntime != 0)
        r.mutationTesterRuntime = p.mutationTesterRuntime.dur!"msecs";

    if (p.compileDb.length != 0) {
        try {
            r.compileDb = p.compileDb.fromArgCompileDb;
        }
        catch (Exception e) {
            logger.error(e.msg);
            throw new Exception("Unable to open compile commands database(s)");
        }
    }

    return r;
}

private:

ExitStatusType runMutate(Frontend fe) @trusted {
    import dextool.compilation_db : CompileCommandFilter,
        defaultCompilerFlagFilter;
    import dextool.user_filerange;
    import dextool.plugin.mutate.backend : Database;

    auto db = Database.make(fe.db, fe.rawUserData.mutationOrder);

    return () @safe{
        auto fe_io = new FrontendIO(fe.restrictDir, fe.outputDirectory, fe.rawUserData.dryRun);
        scope (success)
            fe_io.release;
        auto fe_validate = new FrontendValidateLoc(fe.restrictDir, fe.outputDirectory);

        auto default_filter = CompileCommandFilter(defaultCompilerFlagFilter, 1);
        auto frange = UserFileRange(fe.compileDb, fe.rawUserData.inFiles,
                fe.rawUserData.cflags, default_filter);

        logger.trace("ToolMode: ", fe.rawUserData.toolMode);

        final switch (fe.rawUserData.toolMode) {
        case ToolMode.none:
            logger.error("No mode specified");
            return ExitStatusType.Errors;
        case ToolMode.analyzer:
            import dextool.plugin.mutate.backend : runAnalyzer;

            return runAnalyzer(db, frange, fe_validate, fe_io);
        case ToolMode.generate_mutant:
            import dextool.plugin.mutate.backend : runGenerateMutant;

            return runGenerateMutant(db, fe.rawUserData.mutation,
                    fe.rawUserData.mutationId, fe_io, fe_validate);
        case ToolMode.test_mutants:
            import dextool.plugin.mutate.backend : makeTestMutant;

            return makeTestMutant.mutations(fe.rawUserData.mutation)
                .testSuiteProgram(fe.mutationTester).compileProgram(fe.mutationCompile)
                .testCaseAnalyzeProgram(fe.mutationTestCaseAnalyze).testSuiteTimeout(fe.mutationTesterRuntime)
                .testCaseAnalyzeBuiltin(fe.rawUserData.mutationTestCaseBuiltin).run(db, fe_io);
        case ToolMode.report:
            import dextool.plugin.mutate.backend : runReport;

            return runReport(db, fe.rawUserData.mutation, fe.rawUserData.reportKind,
                    fe.rawUserData.reportLevel, fe.rawUserData.reportSection, fe_io);
        case ToolMode.admin:
            import dextool.plugin.mutate.backend : makeAdmin;

            return makeAdmin().operation(fe.rawUserData.adminOp).mutations(fe.rawUserData.mutation)
                .fromStatus(fe.rawUserData.mutantStatus).toStatus(fe.rawUserData.mutantToStatus)
                .testCaseRegex(fe.rawUserData.testCaseRegex).run(db);
        }
    }();
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
    import std.exception : collectException;
    import std.stdio : File;
    import dextool.type : AbsolutePath;
    import dextool.plugin.mutate.backend : SafeOutput, SafeInput;
    import dextool.vfs : VirtualFileSystem, VfsFile;

    VirtualFileSystem vfs;

    private AbsolutePath[] restrict_dir;
    private AbsolutePath output_dir;
    private bool dry_run;

    this(AbsolutePath[] restrict_dir, AbsolutePath output_dir, bool dry_run) {
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

    override SafeOutput makeOutput(AbsolutePath p) @safe {
        verifyPathInsideRoot(output_dir, p, dry_run);
        return SafeOutput(p, this);
    }

    override SafeInput makeInput(AbsolutePath p) @safe {
        import std.file;

        verifyPathInsideRoot(output_dir, p, dry_run);

        auto f = vfs.open(cast(FileName) p);
        return SafeInput(f[]);
    }

    override void putFile(AbsolutePath fname, const(ubyte)[] data) @safe {
        import std.stdio : File;

        // because a SafeInput/SafeOutput could theoretically be created via
        // other means than a FilesysIO.
        // TODO fix so this validate is not needed.
        verifyPathInsideRoot(output_dir, fname, dry_run);
        if (!dry_run)
            File(fname, "w").rawWrite(data);
    }

private:
    // assuming that root is already a realpath
    static void verifyPathInsideRoot(AbsolutePath root, AbsolutePath p, bool dry_run) {
        import std.format : format;
        import std.string : startsWith;

        auto realp = p.toRealPath;

        if (!dry_run && !realp.startsWith((cast(string) root))) {
            logger.tracef("Path '%s' escaping output directory (--out) '%s'", realp, root);
            throw new Exception(format("Path '%s' escaping output directory (--out) '%s'",
                    realp, root));
        }
    }
}

final class FrontendValidateLoc : ValidateLoc {
    private AbsolutePath[] restrict_dir;
    private AbsolutePath output_dir;

    this(AbsolutePath[] restrict_dir, AbsolutePath output_dir) {
        this.restrict_dir = restrict_dir;
        this.output_dir = output_dir;
    }

    override AbsolutePath getOutputDir() nothrow {
        return this.output_dir;
    }

    override bool shouldAnalyze(AbsolutePath p) {
        return this.shouldAnalyze(cast(string) p);
    }

    override bool shouldAnalyze(const string p) {
        import std.algorithm : any;
        import std.string : startsWith;

        auto realp = p.toRealPath;

        bool res = any!(a => realp.startsWith(a))(restrict_dir);
        logger.tracef(!res, "Path '%s' do not match any of [%(%s, %)]", realp, restrict_dir);
        return res;
    }

    override bool shouldMutate(AbsolutePath p) {
        import std.string : startsWith;

        auto realp = p.toRealPath;

        bool res = realp.toRealPath.startsWith(output_dir);
        logger.tracef(!res, "Path '%s' escaping output directory (--out) '%s'", realp, output_dir);
        return res;
    }
}

/** Convert a string to the "real path" by resolving all symlinks resulting in an absolute path.

TODO: optimize
This function is very inefficient. It creates a lot of GC garbage.
It should also be moved to source/dextool in the future to be able to be re-used by other components.
Maybe even integrated in AbsolutePath.

trusted: orig_p is a string. A string is assured by the language to be memory
safe. Thus this function that operates on strings as input are memory safe for
all possible input.
  */
string toRealPath(const string orig_p) @trusted {
    import core.sys.posix.stdlib : realpath;
    import core.stdc.stdlib : free;
    import std.string : toStringz, fromStringz;

    auto p = orig_p.toStringz;
    auto absp = realpath(p, null);
    scope (exit) {
        if (absp)
            free(absp);
    }

    if (absp is null)
        return orig_p;
    else
        return absp.fromStringz.idup;
}
