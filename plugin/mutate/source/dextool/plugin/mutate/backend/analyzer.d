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

import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter,
    CompileCommandDB;
import dextool.set;
import dextool.type : ExitStatusType, AbsolutePath, Path, DirName;
import dextool.user_filerange;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath;
import dextool.plugin.mutate.backend.visitor : makeRootVisitor;

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(ref Database db, ref UserFileRange frange,
        ValidateLoc val_loc, FilesysIO fio) @safe {
    import std.algorithm : map;
    import std.path : relativePath;
    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.utility.virtualfilesystem;
    import dextool.clang : findFlags;
    import dextool.plugin.mutate.backend.type : Language;
    import dextool.type : FileName, Exists, makeExists;
    import dextool.utility : analyzeFile;

    // they are not by necessity the same.
    // Input could be a file that is excluded via --restrict but pull in a
    // header-only library that is allowed to be mutated.
    Set!AbsolutePath analyzed_files;
    Set!AbsolutePath files_with_mutations;

    foreach (in_file; frange) {
        // find the file and flags to analyze

        Exists!AbsolutePath checked_in_file;
        try {
            checked_in_file = makeExists(in_file.absoluteFile);
        } catch (Exception e) {
            logger.warning(e.msg);
            continue;
        }

        if (analyzed_files.contains(checked_in_file)) {
            continue;
        }

        analyzed_files.add(checked_in_file);

        // analyze the file
        () @trusted{
            auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
            auto root = makeRootVisitor(fio, val_loc);
            analyzeFile(checked_in_file, in_file.cflags, root.visitor, ctx);

            foreach (a; root.mutationPointFiles) {
                auto abs_path = AbsolutePath(a.path.FileName);
                analyzed_files.add(abs_path);
                files_with_mutations.add(abs_path);

                auto relp = trustedRelativePath(a.path.FileName, fio.getOutputDir);

                try {
                    auto f_status = isFileChanged(db, AbsolutePath(a.path.FileName,
                            DirName(fio.getOutputDir)), fio);
                    if (f_status == FileStatus.changed) {
                        logger.infof("Updating analyze of '%s'", a);
                        db.removeFile(relp);
                    }

                    auto cs = checksum(ctx.virtualFileSystem.open(a.path.FileName)[]);
                    db.put(Path(relp), cs, a.lang);
                } catch (Exception e) {
                    logger.warning(e.msg);
                }
            }

            db.put(root.mutationPoints, fio.getOutputDir);
        }();
    }

    prune(db, files_with_mutations, fio.getOutputDir);

    return ExitStatusType.Ok;
}

private:

enum FileStatus {
    noChange,
    notInDatabase,
    changed
}

/// Prune the database of files that has been removed since last analysis.
void prune(ref Database db, ref const Set!AbsolutePath analyzed_files, const AbsolutePath root_dir) @safe {
    import dextool.type : FileName;

    foreach (const f; db.getFiles) {
        auto abs_f = AbsolutePath(FileName(f), DirName(cast(string) root_dir));

        if (analyzed_files.contains(abs_f))
            continue;

        logger.infof("Removed from files to mutate: '%s'", abs_f);
        db.removeFile(f);
    }
}

FileStatus isFileChanged(ref Database db, AbsolutePath p, FilesysIO fio) @safe {
    auto relp = trustedRelativePath(p, fio.getOutputDir);

    if (!db.isAnalyzed(relp))
        return FileStatus.notInDatabase;

    auto db_checksum = db.getFileChecksum(relp);
    auto f_checksum = checksum(fio.makeInput(p).read[]);

    auto rval = (!db_checksum.isNull && db_checksum != f_checksum) ? FileStatus.changed
        : FileStatus.noChange;
    debug logger.trace(rval == FileStatus.changed, "db: ", db_checksum, " file: ", f_checksum);

    return rval;
}
