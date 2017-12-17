/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-plugin_mutate_analyzer
*/
module dextool.plugin.mutate.backend.analyzer;

import logger = std.experimental.logger;

import dextool.plugin.mutate.backend.database : Database;

import dextool.type : ExitStatusType, AbsolutePath, Path;
import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter,
    CompileCommandDB;
import dextool.user_filerange;

import dextool.plugin.mutate.backend.interface_ : ValidateLoc;
import dextool.plugin.mutate.backend.visitor : ExpressionVisitor;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath;

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(ref Database db, ref UserFileRange frange, ValidateLoc val_loc) @safe {
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

        if (checked_in_file in analyzed_files || db.isAnalyzed(checked_in_file))
            continue;
        analyzed_files[checked_in_file] = true;

        // analye the file
        auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        auto visitor = new ExpressionVisitor(val_loc);
        analyzeFile(checked_in_file, in_file.cflags, visitor, ctx);

        foreach (a; visitor.mutationPointFiles.map!(a => FileName(a))) {
            auto relp = trustedRelativePath(a, val_loc.getRestrictDir);

            try {
                auto cs = checksum(ctx.virtualFileSystem.slice!(ubyte[])(a));
                db.put(Path(relp), cs);
            }
            catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        db.put(visitor.mutationPoints, val_loc.getRestrictDir);
    }

    return ExitStatusType.Ok;
}

private:

/**
 * trusted: no validation that the read data is a string.
 */
ubyte[] safeRead(AbsolutePath p) @trusted nothrow {
    import std.file;
    import std.exception : collectException;

    try {
        return cast(ubyte[]) std.file.read(p);
    }
    catch (Exception e) {
        collectException(logger.warning(e.msg));
    }

    return null;
}
