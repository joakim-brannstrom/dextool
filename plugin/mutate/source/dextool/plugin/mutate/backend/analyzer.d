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
module dextool.plugin.mutate.backend.analyzer;

import logger = std.experimental.logger;

import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter, CompileCommandDB;
import dextool.set;
import dextool.type : ExitStatusType, AbsolutePath, Path, DirName;
import dextool.user_filerange;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath, Checksum;
import dextool.plugin.mutate.backend.visitor : makeRootVisitor;

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(ref Database db, ref UserFileRange frange,
        ValidateLoc val_loc, FilesysIO fio) @safe {
    auto analyzer = Analyzer(db, val_loc, fio);

    foreach (in_file; frange)
        analyzer.process(in_file);
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
    }

    this(ref Database db, ValidateLoc val_loc, FilesysIO fio) @trusted {
        this.db = &db;
        this.before_files = db.getFiles.setFromList;
        this.val_loc = val_loc;
        this.fio = fio;

        db.removeAllFiles;
    }

    void process(Nullable!SearchResult in_file) @safe {
        if (in_file.isNull)
            return;

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

        // analyze the file
        () @trusted {
            auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
            auto root = makeRootVisitor(fio, val_loc);
            analyzeFile(checked_in_file, in_file.cflags, root.visitor, ctx);

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
        }();
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
