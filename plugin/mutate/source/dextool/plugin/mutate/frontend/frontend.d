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

import dextool.plugin.mutate.frontend.argparser;
import dextool.plugin.mutate.type : MutationOrder, ReportKind, MutationKind,
    ReportLevel, AdminOperation;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.utility;

@safe:

ExitStatusType runMutate(ArgParser conf) {
    logger.trace("ToolMode: ", conf.data.toolMode);

    alias Func1 = ExitStatusType function(ref ArgParser conf, ref DataAccess dacc) @safe;
    Func1[ToolMode] modes;

    modes[ToolMode.analyzer] = &modeAnalyze;
    modes[ToolMode.generate_mutant] = &modeGenerateMutant;
    modes[ToolMode.test_mutants] = &modeTestMutants;
    modes[ToolMode.report] = &modeReport;
    modes[ToolMode.admin] = &modeAdmin;

    if (auto f = conf.toolMode in modes) {
        return () @trusted{
            auto dacc = DataAccess.make(conf);
            scope (exit)
                dacc.io.release;
            return (*f)(conf, dacc);
        }();
    }

    switch (conf.toolMode) {
    case ToolMode.none:
        logger.error("No mode specified");
        return ExitStatusType.Errors;
    case ToolMode.dumpConfig:
        return modeDumpFullConfig(conf);
    case ToolMode.initConfig:
        return modeInitConfig(conf);
    default:
        logger.error("Mode not supported. This should not happen. Contact the maintainer of dextool: ",
                conf.data.toolMode);
        return ExitStatusType.Errors;
    }
}

private:

import dextool.plugin.mutate.backend : FilesysIO, ValidateLoc;

struct DataAccess {
    import dextool.compilation_db : CompileCommandFilter,
        defaultCompilerFlagFilter, fromArgCompileDb;
    import dextool.plugin.mutate.backend : Database;
    import dextool.user_filerange;

    Database db;
    FrontendIO io;
    FrontendValidateLoc validateLoc;
    UserFileRange frange;
    CompileCommandDB fusedCompileDb;

    static auto make(ref ArgParser conf) @trusted {
        CompileCommandDB fusedCompileDb;
        if (conf.compileDb.dbs.length != 0) {
            try {
                fusedCompileDb = conf.compileDb.dbs.fromArgCompileDb;
            } catch (Exception e) {
                logger.error(e.msg);
                throw new Exception("Unable to open compile commands database(s)");
            }
        }

        auto fe_io = new FrontendIO(conf.workArea.restrictDir,
                conf.workArea.outputDirectory, conf.mutationTest.dryRun);
        auto fe_validate = new FrontendValidateLoc(conf.workArea.restrictDir,
                conf.workArea.outputDirectory);
        auto frange = UserFileRange(fusedCompileDb, conf.data.inFiles,
                conf.compiler.extraFlags, conf.compileDb.flagFilter);

        return DataAccess(Database.make(conf.db, conf.mutationTest.mutationOrder),
                fe_io, fe_validate, frange, fusedCompileDb);
    }
}

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

ExitStatusType modeDumpFullConfig(ref ArgParser conf) @safe {
    import std.stdio : writeln, stderr;

    () @trusted{
        // make it easy for a user to pipe the output to the config file
        stderr.writeln("Dumping the configuration used. The format is TOML (.toml)");
        stderr.writeln("If you want to use it put it in your '.dextool_mutate.toml'");
    }();

    writeln(conf.toTOML);

    return ExitStatusType.Ok;
}

ExitStatusType modeInitConfig(ref ArgParser conf) @safe {
    import std.stdio : File;
    import std.file : exists;

    if (exists(conf.miniConf.confFile)) {
        logger.error("Configuration file already exists: ", conf.miniConf.confFile);
        return ExitStatusType.Errors;
    }

    try {
        File(conf.miniConf.confFile, "w").write(conf.toTOML);
        logger.info("Wrote configuration to ", conf.miniConf.confFile);
        return ExitStatusType.Ok;
    } catch (Exception e) {
        logger.error(e.msg);
    }

    return ExitStatusType.Errors;
}

ExitStatusType modeAnalyze(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : runAnalyzer;

    return runAnalyzer(dacc.db, dacc.frange, dacc.validateLoc, dacc.io);
}

ExitStatusType modeGenerateMutant(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : runGenerateMutant;

    return runGenerateMutant(dacc.db, conf.data.mutation, conf.data.mutationId,
            dacc.io, dacc.validateLoc);
}

ExitStatusType modeTestMutants(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : makeTestMutant;

    return makeTestMutant.mutations(conf.data.mutation).testSuiteProgram(conf.mutationTest.mutationTester)
        .compileProgram(conf.mutationTest.mutationCompile).testCaseAnalyzeProgram(
                conf.mutationTest.mutationTestCaseAnalyze)
        .testSuiteTimeout(conf.mutationTest.mutationTesterRuntime)
        .testCaseAnalyzeBuiltin(conf.mutationTest.mutationTestCaseBuiltin).run(dacc.db, dacc.io);
}

ExitStatusType modeReport(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : runReport;

    return runReport(dacc.db, conf.data.mutation, conf.report, dacc.io);
}

ExitStatusType modeAdmin(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : makeAdmin;

    return makeAdmin().operation(conf.admin.adminOp).mutations(conf.data.mutation)
        .fromStatus(conf.admin.mutantStatus).toStatus(conf.admin.mutantToStatus)
        .testCaseRegex(conf.admin.testCaseRegex).run(dacc.db);
}
