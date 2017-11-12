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

import std.typecons : Nullable;
import logger = std.experimental.logger;

import dextool.compilation_db : SearchResult, CompileCommandDB,
    CompileCommandFilter, CompileCommand, parseFlag;
import dextool.type : FileName, AbsolutePath;

@safe:

private struct IncludeResult {
    /// The entry that had an #include with the desired file
    CompileCommand original;

    /// The compile command derived from the original with adjusted file and
    /// absoluteFile.
    CompileCommand derived;
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
Nullable!IncludeResult findCompileCommandFromIncludes(ref CompileCommandDB compdb,
        FileName fname, ref const CompileCommandFilter flag_filter, const string[] extra_flags) {
    import std.algorithm : filter;
    import std.file : exists;
    import std.path : baseName;
    import std.typecons : Yes;

    import cpptooling.analyzer.clang.check_parse_result : hasParseErrors,
        logDiagnostic;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.analyzer.clang.include_visitor : hasInclude;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    string find_file = fname.baseName;

    bool isMatch(string include) {
        return find_file == include.baseName;
    }

    Nullable!IncludeResult r;

    foreach (entry; compdb.filter!(a => exists(a.absoluteFile))) {
        auto flags = extra_flags ~ entry.parseFlag(flag_filter);
        auto translation_unit = ctx.makeTranslationUnit(entry.absoluteFile, flags);

        if (translation_unit.hasParseErrors) {
            logger.warningf("Skipping '%s' because of compilation errors", entry.absoluteFile);
            logDiagnostic(translation_unit);
            continue;
        }

        auto found = translation_unit.cursor.hasInclude!isMatch();
        if (!found.isNull) {
            r = IncludeResult();
            r.original = entry;
            r.derived = entry;
            r.derived.file = found.get;
            r.derived.absoluteFile = CompileCommand.AbsoluteFileName(entry.directory, found.get);
            return r;
        }
    }

    return r;
}

/// Find flags for fname by searching in the compilation DB.
Nullable!SearchResult findFlags(ref CompileCommandDB compdb, FileName fname,
        const string[] flags, ref const CompileCommandFilter flag_filter) {
    import std.file : exists;
    import std.path : baseName;
    import std.string : join;

    import dextool.compilation_db : appendOrError;

    typeof(return) rval;

    auto db_search_result = compdb.appendOrError(flags, fname, flag_filter);
    if (!db_search_result.isNull) {
        rval = SearchResult(db_search_result.cflags, db_search_result.absoluteFile);
        logger.trace("Compiler flags: ", rval.cflags.join(" "));
        return rval;
    }

    logger.warningf(`Analyzing all files in the compilation DB for one that has an '#include "%s"'`,
            fname.baseName);

    auto sres = compdb.findCompileCommandFromIncludes(fname, flag_filter, flags);
    if (sres.isNull) {
        logger.error("Unable to find any compiler flags for: ", fname);
        return rval;
    }

    // check if the file from the user is directly accessable on the filesystem.
    // in such a case assume that the located file is the one the user want to parse.
    // otherwise derive it from the compile command DB.
    auto p = AbsolutePath(fname);

    if (!exists(p)) {
        logger.tracef("Unable to locate '%s' on the filesystem", p);
        p = sres.derived.absoluteFile;
        logger.tracef("Using the filename from the compile DB instead '%s'", p);
    }

    logger.warningf(`Using compiler flags derived from '%s' because it has an '#include' for '%s'`,
            sres.original.absoluteFile, sres.derived.absoluteFile);

    rval = SearchResult(flags ~ sres.derived.parseFlag(flag_filter), p);
    // the user may want to see the flags but usually uninterested
    logger.trace("Compiler flags: ", rval.cflags.join(" "));

    return rval;
}
