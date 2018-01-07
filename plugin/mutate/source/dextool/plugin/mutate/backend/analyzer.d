/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-plugin_mutate_analyzer

TODO cache the checksums. They are *heavy*.
*/
module dextool.plugin.mutate.backend.analyzer;

import logger = std.experimental.logger;

import dextool.plugin.mutate.backend.database : Database;

import dextool.type : ExitStatusType, AbsolutePath, Path, DirName;
import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter,
    CompileCommandDB;
import dextool.user_filerange;

import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.visitor : makeRootVisitor;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath;

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
    import dextool.type : FileName, Exists, makeExists;
    import dextool.utility : analyzeFile;

    bool[string] analyzed_files;
    foreach (in_file; frange) {
        // find the file and flags to analyze

        Exists!AbsolutePath checked_in_file;
        try {
            checked_in_file = makeExists(in_file.absoluteFile);
        }
        catch (Exception e) {
            logger.warning(e.msg);
            continue;
        }

        if (checked_in_file in analyzed_files) {
            continue;
        }

        analyzed_files[checked_in_file] = true;

        // analye the file
        auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        auto root = makeRootVisitor(val_loc);
        analyzeFile(checked_in_file, in_file.cflags, root.visitor, ctx);

        foreach (a; root.mutationPointFiles.map!(a => FileName(a))) {
            auto relp = trustedRelativePath(a, val_loc.getRestrictDir);

            try {
                auto f_status = isFileChanged(db, AbsolutePath(a,
                        DirName(fio.getRestrictDir)), fio);
                if (f_status == FileStatus.changed) {
                    logger.infof("Updating analyze of '%s'", a);
                    db.removeFile(relp);
                }

                auto cs = checksum(ctx.virtualFileSystem.slice!(ubyte[])(a));
                db.put(Path(relp), cs);
            }
            catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        db.put(root.mutationPoints, val_loc.getRestrictDir);
    }

    return ExitStatusType.Ok;
}

private:

enum FileStatus {
    noChange,
    notInDatabase,
    changed
}

FileStatus isFileChanged(ref Database db, AbsolutePath p, FilesysIO fio) @safe {
    auto relp = trustedRelativePath(p, fio.getRestrictDir);

    if (!db.isAnalyzed(relp))
        return FileStatus.notInDatabase;

    auto db_checksum = db.getFileChecksum(relp);
    auto f_checksum = checksum(fio.makeInput(p).read[]);

    auto rval = (!db_checksum.isNull && db_checksum != f_checksum) ? FileStatus.changed
        : FileStatus.noChange;
    debug logger.trace(rval == FileStatus.changed, "db: ", db_checksum, " file: ", f_checksum);

    return rval;
}
