/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains helpers for interactive with the clang abstractions.
*/
module dextool.clang;

import logger = std.experimental.logger;
import std.algorithm : filter, map;
import std.array : appender, array, empty;
import std.file : exists, getcwd;
import std.path : baseName, buildPath;
import std.typecons : Nullable, Yes;

import dextool.compilation_db : CompileCommandDB, LimitFileRange, ParsedCompileCommand,
    ParseFlags, CompileCommandFilter, CompileCommand, parseFlag, DbCompiler = Compiler;
import dextool.type : Path, AbsolutePath;

@safe:

struct IncludeResult {
    /// The entry that had an #include with the desired file
    ParsedCompileCommand original;

    /// The compile command derived from the original with adjusted file and
    /// absoluteFile.
    ParsedCompileCommand derived;
}

/// Find the path on the filesystem where f exists as if the compiler search for the file.
Nullable!AbsolutePath findFile(Path f, ParseFlags.Include[] includes, AbsolutePath dir) {
    typeof(return) rval;

    foreach (a; includes.map!(a => buildPath(cast(string) dir, a, f))
            .filter!(a => exists(a))) {
        rval = AbsolutePath(Path(a));
        break;
    }
    return rval;
}

/** Find a CompileCommand that in any way have an `#include` which pull in fname.
 *
 * This is useful to find the flags needed to parse a header file which is used
 * by the implementation.
 *
 * Note that the context will be expanded with the flags.
 *
 * Returns: The first CompileCommand object which _probably_ has the flags needed to parse fname.
 */
Nullable!IncludeResult findCompileCommandFromIncludes(ParsedCompileCommand[] compdb, Path fname) @trusted {
    import cpptooling.analyzer.clang.check_parse_result : hasParseErrors, logDiagnostic;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.analyzer.clang.include_visitor : hasInclude;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    string find_file = fname.baseName;

    bool isMatch(string include) {
        return find_file == include.baseName;
    }

    typeof(return) r;

    foreach (entry; compdb.filter!(a => exists(a.cmd.absoluteFile))) {
        auto translation_unit = ctx.makeTranslationUnit(entry.cmd.absoluteFile,
                entry.flags.completeFlags);

        if (translation_unit.hasParseErrors) {
            logger.infof("Skipping '%s' because of compilation errors", entry.cmd.absoluteFile);
            logDiagnostic(translation_unit);
            continue;
        }

        auto found = translation_unit.cursor.hasInclude!isMatch();
        if (!found.isNull) {
            r = IncludeResult.init;
            r.get.original = entry;
            r.get.derived = entry;
            r.get.derived.cmd.file = found.get;
            auto onDisc = findFile(found.get, entry.flags.includes, entry.cmd.directory);
            if (onDisc.isNull) {
                // wild guess
                r.get.derived.cmd.absoluteFile = AbsolutePath(Path(buildPath(entry.cmd.directory,
                        found.get)));
            } else {
                r.get.derived.cmd.absoluteFile = onDisc.get;
            }

            return r;
        }
    }

    return r;
}

/** Try and find matching compiler flags for the missing files.
 *
 * Returns: an updated LimitFileRange where those that where found have been moved from `missingFiles` to `commands`.
 */
auto reduceMissingFiles(LimitFileRange lfr, ParsedCompileCommand[] db) {
    import std.algorithm : canFind;

    if (db.empty || lfr.isMissingFilesEmpty)
        return lfr;

    auto found = appender!(string[])();
    auto newCmds = appender!(ParsedCompileCommand[])();

    foreach (f; lfr.missingFiles) {
        logger.infof(`Analyzing all files in the compilation DB for one that has an '#include "%s"'`,
                f.baseName);

        auto res = findCompileCommandFromIncludes(db, Path(f));
        if (res.isNull) {
            continue;
        }

        logger.infof(`Using compiler flags derived from '%s' because it has an '#include' for '%s'`,
                res.get.original.cmd.absoluteFile, res.get.derived.cmd.absoluteFile);

        ParsedCompileCommand cmd = res.get.derived;

        if (exists(f)) {
            // check if the file from the user is directly accessable on the
            // filesystem. In such a case assume that the located file is the
            // one the user want to parse. Otherwise derive it from the compile
            // command DB.
            cmd.cmd.file = Path(f);
            cmd.cmd.absoluteFile = AbsolutePath(Path(buildPath(cmd.cmd.directory, f)));
        } else {
            logger.tracef("Unable to locate '%s' on the filesystem", f);
            logger.tracef("Using the filename from the compile DB instead '%s'",
                    cmd.cmd.absoluteFile);
        }

        newCmds.put(cmd);
        found.put(f);
    }

    lfr.commands ~= newCmds.data;
    lfr.missingFiles = lfr.missingFiles.filter!(a => !found.data.canFind(a)).array;
    return lfr;
}
