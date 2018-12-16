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

import dextool.plugin.mutate.backend.analyze.internal : Cache;
import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath, Checksum;
import dextool.plugin.mutate.backend.visitor : makeRootVisitor;
import dextool.plugin.mutate.config : ConfigCompiler;

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(ref Database db, ConfigCompiler conf,
        ref UserFileRange frange, ValidateLoc val_loc, FilesysIO fio) @safe {
    auto analyzer = Analyzer(db, val_loc, fio, conf);

    foreach (in_file; frange) {
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
    import std.typecons : NullableRef, Nullable, Yes;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.utility.virtualfilesystem;
    import dextool.compilation_db : SearchResult;
    import dextool.type : FileName, Exists, makeExists;
    import dextool.utility : analyzeFile;

    private {
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
    }

    this(ref Database db, ValidateLoc val_loc, FilesysIO fio, ConfigCompiler conf) @trusted {
        this.db = &db;
        this.before_files = db.getFiles.setFromList;
        this.val_loc = val_loc;
        this.fio = fio;
        this.cache = new Cache;

        db.removeAllFiles;
    }

    void process(Nullable!SearchResult in_file) @safe {
        if (in_file.isNull)
            return;

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

            auto files = analyzeForMutants(in_file, checked_in_file, ctx);
            foreach (f; files)
                analyzeForComments(f, ctx);
        }();
    }

    Path[] analyzeForMutants(SearchResult in_file,
            Exists!AbsolutePath checked_in_file, ref ClangContext ctx) @safe {
        import std.algorithm : map;
        import std.array : array;

        auto root = makeRootVisitor(fio, val_loc, cache);
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

    void analyzeForComments(Path file, ref ClangContext ctx) @trusted {
        import std.algorithm : filter, countUntil, among, startsWith;
        import std.array : appender;
        import std.string : stripLeft;
        import std.utf : byCodeUnit;
        import std.functional : memoize;
        import clang.c.Index : CXTokenKind;
        import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr;

        Nullable!FileId getFileIdImpl(string path) {
            return db.getFileId(trustedRelativePath(path, fio.getOutputDir).Path);
        }

        alias getFileId = memoize!getFileIdImpl;

        auto tu = ctx.makeTranslationUnit(file);

        auto mdata = appender!(LineMetadata[])();
        bool print_found = true;
        foreach (t; tu.cursor.tokens.filter!(a => a.kind == CXTokenKind.comment)) {
            auto txt = t.spelling.stripLeft;
            const index = txt.byCodeUnit.countUntil!(a => !a.among('/', '*'));
            if (index >= txt.length || !txt[0 .. index].among("//", "/*"))
                continue;

            txt = txt[index .. $].stripLeft;

            if (!txt.startsWith("NOMUT"))
                continue;

            const fname = t.location.file.name;
            auto fid = getFileId(fname);
            auto ext = t.extent;
            auto start = ext.start;

            if (fid.isNull) {
                logger.tracef("File with suppressed mutants (// NOMUT) not in the DB: %s:%s",
                        fname, start);
                continue;
            }

            mdata.put(LineMetadata(fid, start.line, LineAttr.noMut));
            logger.trace(print_found, "// NOMUT found in ", file);
            print_found = false;
        }

        db.put(mdata.data);
    }

    void finalize() @safe {
        db.removeOrphanedMutants;
        printPrunedFiles(before_files, files_with_mutations, fio.getOutputDir);
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

    foreach (const f; setToRange!Path(before_files)) {
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
