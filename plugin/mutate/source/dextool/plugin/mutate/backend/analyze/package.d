/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-analyzer

TODO cache the checksums. They are *heavy*.
*/
module dextool.plugin.mutate.backend.analyze;

import logger = std.experimental.logger;

import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter, CompileCommandDB;
import dextool.set;
import dextool.type : ExitStatusType, AbsolutePath, Path, DirName;
import dextool.user_filerange;

import dextool.plugin.mutate.backend.analyze.internal : Cache, TokenStream;
import dextool.plugin.mutate.backend.analyze.visitor : makeRootVisitor;
import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.database.type : MarkedMutant;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath, Checksum;
import dextool.plugin.mutate.config : ConfigCompiler, ConfigAnalyze;
import dextool.plugin.mutate.backend.report.utility : statusToString, Table;

version (unittest) {
    import unit_threaded.assertions;
}

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(ref Database db, ConfigAnalyze conf_analyze,
        ConfigCompiler conf_compiler, UserFileRange frange, ValidateLoc val_loc, FilesysIO fio) @trusted {
    import std.algorithm : filter, map;

    auto analyzer = Analyzer(db, val_loc, fio, conf_compiler);

    foreach (in_file; frange.filter!(a => !a.isNull)
            .map!(a => a.get)
            .filter!(a => !isPathInsideAnyRoot(conf_analyze.exclude, a.absoluteFile))) {
        try {
            analyzer.process(in_file);
        } catch (Exception e) {
            () @trusted { logger.trace(e); logger.warning(e.msg); }();
        }
    }
    analyzer.finalize;

    return ExitStatusType.Ok;
}

private:

struct Analyzer {
    import std.regex : Regex, regex, matchFirst;
    import std.typecons : NullableRef, Nullable, Yes;
    import miniorm : Transaction;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.utility.virtualfilesystem;
    import dextool.compilation_db : SearchResult;
    import dextool.type : FileName, Exists, makeExists;
    import dextool.utility : analyzeFile;

    private {
        static immutable raw_re_nomut = `^((//)|(/\*))\s*NOMUT\s*(\((?P<tag>.*)\))?\s*((?P<comment>.*)\*/|(?P<comment>.*))?`;

        // they are not by necessity the same.
        // Input could be a file that is excluded via --restrict but pull in a
        // header-only library that is allowed to be mutated.
        Set!AbsolutePath analyzed_files;
        Set!AbsolutePath files_with_mutations;

        Set!Path before_files;

        NullableRef!Database db;

        ValidateLoc val_loc;
        FilesysIO fio;
        ConfigCompiler conf;

        Cache cache;

        Regex!char re_nomut;

        Transaction trans;
    }

    this(ref Database db, ValidateLoc val_loc, FilesysIO fio, ConfigCompiler conf) @trusted {
        this.db = &db;
        this.before_files = db.getFiles.toSet;
        this.val_loc = val_loc;
        this.fio = fio;
        this.conf = conf;
        this.cache = new Cache;
        this.re_nomut = regex(raw_re_nomut);

        trans = db.transaction;
        db.removeAllFiles;
    }

    void process(SearchResult in_file) @safe {
        // TODO: this should be generic for Dextool.
        in_file.flags.forceSystemIncludes = conf.forceSystemIncludes;

        // find the file and flags to analyze
        Exists!AbsolutePath checked_in_file;
        try {
            checked_in_file = makeExists(in_file.absoluteFile);
        } catch (Exception e) {
            logger.warning(e.msg);
            return;
        }

        if (analyzed_files.contains(checked_in_file))
            return;

        analyzed_files.add(checked_in_file);

        () @trusted {
            auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
            auto tstream = new TokenStreamImpl(ctx);

            auto files = analyzeForMutants(in_file, checked_in_file, ctx, tstream);
            // TODO: filter files so they are only analyzed once for comments
            foreach (f; files)
                analyzeForComments(f, tstream);
        }();
    }

    Path[] analyzeForMutants(SearchResult in_file,
            Exists!AbsolutePath checked_in_file, ref ClangContext ctx, TokenStream tstream) @safe {
        import std.algorithm : map;
        import std.array : array;

        auto root = makeRootVisitor(fio, val_loc, tstream, cache);
        analyzeFile(checked_in_file, in_file.flags.completeFlags, root.visitor, ctx);

        foreach (a; root.mutationPointFiles) {
            auto abs_path = AbsolutePath(a.path.FileName);
            analyzed_files.add(abs_path);
            files_with_mutations.add(abs_path);

            auto relp = trustedRelativePath(a.path.FileName, fio.getOutputDir);

            try {
                auto f_status = isFileChanged(db, relp, a.cs);
                if (f_status == FileStatus.changed) {
                    logger.infof("Updating analyze of '%s'", a);
                }

                db.put(Path(relp), a.cs, a.lang);
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        db.put(root.mutationPoints, fio.getOutputDir);
        return root.mutationPointFiles.map!(a => a.path).array;
    }

    /**
     * Tokens are always from the same file.
     */
    void analyzeForComments(Path file, TokenStream tstream) @trusted {
        import std.algorithm : filter, countUntil, among, startsWith;
        import std.array : appender;
        import std.string : stripLeft;
        import std.utf : byCodeUnit;
        import clang.c.Index : CXTokenKind;
        import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr, NoMut;

        const fid = db.getFileId(fio.toRelativeRoot(file));
        if (fid.isNull) {
            logger.warningf("File with suppressed mutants (// NOMUT) not in the DB: %s. Skipping...",
                    file);
            return;
        }

        auto mdata = appender!(LineMetadata[])();
        foreach (t; cache.getTokens(AbsolutePath(file), tstream)
                .filter!(a => a.kind == CXTokenKind.comment)) {
            auto m = matchFirst(t.spelling, re_nomut);
            if (m.whichPattern == 0)
                continue;

            mdata.put(LineMetadata(fid.get, t.loc.line, LineAttr(NoMut(m["tag"], m["comment"]))));
            logger.tracef("NOMUT found at %s:%s:%s", file, t.loc.line, t.loc.column);
        }

        db.put(mdata.data);
    }

    void finalize() @trusted {
        import dextool.plugin.mutate.backend.test_mutant.timeout : resetTimeoutContext;

        resetTimeoutContext(db);
        db.removeOrphanedMutants;
        printLostMarkings(db.getLostMarkings);

        trans.commit;

        printPrunedFiles(before_files, files_with_mutations, fio.getOutputDir);
    }
}

@(
        "shall extract the tag and comment from the input following the pattern NOMUT with optional tag and comment")
unittest {
    import std.regex : regex, matchFirst;
    import unit_threaded.runner.io : writelnUt;

    auto re_nomut = regex(Analyzer.raw_re_nomut);
    // NOMUT in other type of comments should NOT match.
    matchFirst("/// NOMUT", re_nomut).whichPattern.shouldEqual(0);
    matchFirst("// stuff with NOMUT in it", re_nomut).whichPattern.shouldEqual(0);
    matchFirst("/** NOMUT*/", re_nomut).whichPattern.shouldEqual(0);
    matchFirst("/* stuff with NOMUT in it */", re_nomut).whichPattern.shouldEqual(0);

    matchFirst("/*NOMUT*/", re_nomut).whichPattern.shouldEqual(1);
    matchFirst("/*NOMUT*/", re_nomut)["comment"].shouldEqual("");
    matchFirst("//NOMUT", re_nomut).whichPattern.shouldEqual(1);
    matchFirst("// NOMUT", re_nomut).whichPattern.shouldEqual(1);
    matchFirst("// NOMUT (arch)", re_nomut)["tag"].shouldEqual("arch");
    matchFirst("// NOMUT smurf", re_nomut)["comment"].shouldEqual("smurf");
    auto m = matchFirst("// NOMUT (arch) smurf", re_nomut);
    m["tag"].shouldEqual("arch");
    m["comment"].shouldEqual("smurf");
}

/// Stream of tokens excluding comment tokens.
class TokenStreamImpl : TokenStream {
    import std.typecons : NullableRef, nullableRef;
    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.plugin.mutate.backend.type : Token;

    NullableRef!ClangContext ctx;

    /// The context must outlive any instance of this class.
    this(ref ClangContext ctx) {
        this.ctx = nullableRef(&ctx);
    }

    Token[] getTokens(Path p) {
        import dextool.plugin.mutate.backend.utility : tokenize;

        return tokenize(ctx, p);
    }

    Token[] getFilteredTokens(Path p) {
        import std.array : array;
        import std.algorithm : filter;
        import clang.c.Index : CXTokenKind;
        import dextool.plugin.mutate.backend.utility : tokenize;

        // Filter a stream of tokens for those that should affect the checksum.
        return tokenize(ctx, p).filter!(a => a.kind != CXTokenKind.comment).array;
    }
}

enum FileStatus {
    noChange,
    notInDatabase,
    changed
}

/// Print the files that has been removed from the database since last analysis.
void printPrunedFiles(ref Set!Path before_files,
        ref Set!AbsolutePath analyzed_files, const AbsolutePath root_dir) @safe {
    import dextool.type : FileName;

    foreach (const f; before_files.toRange) {
        auto abs_f = AbsolutePath(FileName(f), DirName(cast(string) root_dir));
        logger.infof(!analyzed_files.contains(abs_f), "Removed from files to mutate: '%s'", abs_f);
    }
}

FileStatus isFileChanged(ref Database db, Path relp, Checksum f_checksum) @safe {
    if (!db.isAnalyzed(relp))
        return FileStatus.notInDatabase;

    auto db_checksum = db.getFileChecksum(relp);

    auto rval = (!db_checksum.isNull && db_checksum != f_checksum) ? FileStatus.changed
        : FileStatus.noChange;
    debug logger.trace(rval == FileStatus.changed, "db: ", db_checksum, " file: ", f_checksum);

    return rval;
}

/// Returns: true if `f` is inside any `roots`.
bool isPathInsideAnyRoot(AbsolutePath[] roots, AbsolutePath f) @safe {
    import dextool.utility : isPathInsideRoot;

    foreach (root; roots) {
        if (isPathInsideRoot(root, f))
            return true;
    }

    return false;
}

/// prints a marked mutant that has become lost due to rerun of analyze
void printLostMarkings(MarkedMutant[] lostMutants) {
    import std.array : empty;
    if (lostMutants.empty)
        return;

    import std.stdio: writeln;
    import std.conv : to;

    Table!6 tbl = Table!6(["ID", "File", "Line", "Column", "Status", "Rationale"]);
    foreach(m; lostMutants) {
        typeof(tbl).Row r = [to!string(m.mutationId), m.path, to!string(m.line), to!string(m.column), statusToString(m.toStatus), m.rationale];
        tbl.put(r);
    }
    logger.warning("Marked mutants was lost");
    writeln(tbl);
}
