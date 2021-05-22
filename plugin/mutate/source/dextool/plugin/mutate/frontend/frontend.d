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
import std.array : empty, array;
import std.exception : collectException;
import std.path : buildPath;

import my.filter : GlobFilter;
import my.optional;

import dextool.compilation_db;
import dextool.type : Path, AbsolutePath, ExitStatusType;

import dextool.plugin.mutate.backend : Database;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.frontend.argparser;
import dextool.plugin.mutate.type : MutationOrder, ReportKind, MutationKind, AdminOperation;

@safe:

ExitStatusType runMutate(ArgParser conf) {
    import my.gc : memFree;

    logger.trace("ToolMode: ", conf.data.toolMode);

    auto mfree = memFree;

    alias Func1 = ExitStatusType function(ref ArgParser conf, ref DataAccess dacc) @safe;
    Func1[ToolMode] modes;

    modes[ToolMode.analyzer] = &modeAnalyze;
    modes[ToolMode.generate_mutant] = &modeGenerateMutant;
    modes[ToolMode.test_mutants] = &modeTestMutants;
    modes[ToolMode.report] = &modeReport;
    modes[ToolMode.admin] = &modeAdmin;

    logger.info("Using ", conf.db);

    try
        if (auto f = conf.toolMode in modes) {
            return () @trusted {
                auto dacc = DataAccess.make(conf);
                return (*f)(conf, dacc);
            }();
        } catch (Exception e) {
        logger.error(e.msg);
        return ExitStatusType.Errors;
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

import dextool.plugin.mutate.backend : FilesysIO, ValidateLoc, InvalidPathException;

static InvalidPathException singletonException;

static this() {
    singletonException = new InvalidPathException("Path outside root");
}

struct DataAccess {
    import std.typecons : Nullable;

    import dextool.compilation_db : limitOrAllRange, parse, prependFlags, addCompiler, replaceCompiler,
        addSystemIncludes, fileRange, fromArgCompileDb, ParsedCompileCommandRange, Compiler;

    FrontendIO io;
    FrontendValidateLoc validateLoc;

    ConfigCompileDb compileDb;
    ConfigCompiler compiler;
    string[] inFiles;

    // only generate it on demand. All modes do not require it.
    ParsedCompileCommandRange frange() @trusted {
        import std.algorithm : map, joiner;
        import std.range : only;

        CompileCommandDB fusedCompileDb;
        if (!compileDb.dbs.empty) {
            fusedCompileDb = compileDb.dbs.fromArgCompileDb;
        }

        // dfmt off
        return ParsedCompileCommandRange.make(
            only(fusedCompileDb.fileRange, fileRange(inFiles.map!(a => Path(a)).array, Compiler("/usr/bin/c++"))).joiner
            .parse(compileDb.flagFilter)
            .addCompiler(compiler.useCompilerSystemIncludes)
            .replaceCompiler(compiler.useCompilerSystemIncludes)
            .addSystemIncludes
            .prependFlags(compiler.extraFlags)
            .array);
        // dfmt on
    }

    static auto make(ref ArgParser conf) @trusted {
        auto io = new FrontendIO(conf.workArea.root, conf.mutationTest.dryRun);
        auto validate = new FrontendValidateLoc(conf.workArea.mutantMatcher, conf.workArea.root);

        return DataAccess(io, validate, conf.compileDb, conf.compiler, conf.data.inFiles);
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
 * #SPC-file_security-single_output
 */
final class FrontendIO : FilesysIO {
    import std.stdio : File;
    import blob_model;
    import dextool.plugin.mutate.backend : SafeOutput, Blob;

    BlobVfs vfs;

    private AbsolutePath root;
    private bool dry_run;

    this(AbsolutePath root, bool dry_run) {
        this.root = root;
        this.dry_run = dry_run;
        this.vfs = new BlobVfs;
    }

    override FilesysIO dup() {
        return new FrontendIO(root, dry_run);
    }

    override File getDevNull() {
        return File("/dev/null", "w");
    }

    override File getStdin() @trusted {
        static import std.stdio;

        return std.stdio.stdin;
    }

    override Path toRelativeRoot(Path p) @trusted {
        import std.path : relativePath;

        return relativePath(p, root).Path;
    }

    override AbsolutePath toAbsoluteRoot(Path p) {
        return AbsolutePath(buildPath(root, p));
    }

    override AbsolutePath getOutputDir() @safe pure nothrow @nogc {
        return root;
    }

    override SafeOutput makeOutput(AbsolutePath p) @safe {
        if (!verifyPathInsideRoot(root, p, dry_run))
            throw singletonException;
        return SafeOutput(p, this);
    }

    override Blob makeInput(AbsolutePath p) @safe {
        if (!verifyPathInsideRoot(root, p, dry_run))
            throw singletonException;

        const uri = Uri(cast(string) p);
        if (!vfs.exists(uri)) {
            auto blob = vfs.get(Uri(cast(string) p));
            vfs.open(blob);
        }
        return vfs.get(uri);
    }

    override void putFile(AbsolutePath fname, const(ubyte)[] data) @safe {
        import std.stdio : File;

        // because a Blob/SafeOutput could theoretically be created via
        // other means than a FilesysIO.
        // TODO fix so this validate is not needed.
        if (!dry_run && verifyPathInsideRoot(root, fname, dry_run))
            File(fname, "w").rawWrite(data);
    }

private:
    // assuming that root is already a realpath
    // TODO: replace this function with dextool.utility.isPathInsideRoot
    static bool verifyPathInsideRoot(AbsolutePath root, AbsolutePath p, bool dry_run) {
        import std.format : format;
        import std.string : startsWith;

        if (!dry_run && !p.toString.startsWith(root.toString)) {
            debug logger.tracef(format("Path '%s' escaping output directory (--out) '%s'",
                    p, root));
            return false;
        }
        return true;
    }
}

final class FrontendValidateLoc : ValidateLoc {
    import std.string : startsWith;

    private GlobFilter mutantMatcher;
    private AbsolutePath root;

    this(GlobFilter matcher, AbsolutePath root) {
        this.mutantMatcher = matcher;
        this.root = root;
    }

    override ValidateLoc dup() {
        return new FrontendValidateLoc(mutantMatcher, root);
    }

    override bool isInsideOutputDir(AbsolutePath p) nothrow {
        return p.toString.startsWith(root.toString);
    }

    override AbsolutePath getOutputDir() nothrow {
        return this.root;
    }

    override bool shouldAnalyze(AbsolutePath p) {
        bool res = mutantMatcher.match(p.toString);
        debug logger.tracef(!res, "Path '%s' do not match the glob patterns", p);
        return res;
    }

    /// Returns: if a file should be mutated.
    override bool shouldMutate(AbsolutePath p) {
        import std.file : isDir, exists;

        if (!exists(p) || isDir(p))
            return false;

        bool res = isInsideOutputDir(p);

        if (res) {
            return shouldAnalyze(p);
        }
        return false;
    }
}

ExitStatusType modeDumpFullConfig(ref ArgParser conf) @safe {
    import std.stdio : writeln, stderr;

    () @trusted {
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
    import dextool.plugin.mutate.frontend.argparser : printFileAnalyzeHelp;

    printFileAnalyzeHelp(conf);

    return runAnalyzer(conf.db, conf.data.mutation, conf.analyze,
            conf.compiler, conf.schema, conf.coverage, dacc.frange, dacc.validateLoc, dacc.io);
}

ExitStatusType modeGenerateMutant(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : runGenerateMutant;
    import dextool.plugin.mutate.backend.database.type : MutationId;

    return runGenerateMutant(conf.db, conf.data.mutation,
            MutationId(conf.generate.mutationId), dacc.io, dacc.validateLoc);
}

ExitStatusType modeTestMutants(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : makeTestMutant;

    return makeTestMutant.config(conf.mutationTest).mutations(conf.data.mutation)
        .config(conf.coverage).config(conf.schema).run(conf.db, dacc.io);
}

ExitStatusType modeReport(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : runReport;

    return runReport(conf.db, conf.data.mutation, conf.report, dacc.io);
}

ExitStatusType modeAdmin(ref ArgParser conf, ref DataAccess dacc) {
    import dextool.plugin.mutate.backend : makeAdmin;
    import my.named_type;

    return makeAdmin().operation(conf.admin.adminOp).mutations(conf.data.mutation)
        .mutationsSubKind(conf.admin.subKind).fromStatus(conf.admin.mutantStatus)
        .toStatus(conf.admin.mutantToStatus).testCaseRegex(conf.admin.testCaseRegex).markMutantData(NamedType!(long,
                Tag!"MutationId", 0, Comparable, Hashable, ConvertStringable)(conf.admin.mutationId),
                conf.admin.mutantRationale, dacc.io).database(conf.db).run;
}
