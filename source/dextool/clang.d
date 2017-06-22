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

import dextool.compilation_db;
import dextool.type : FileName, AbsolutePath;

/** Find a CompileCommand that in any way have an `#include` which pull in fname.
 *
 * This is useful to find the flags needed to parse a header file which is used
 * by the implementation.
 *
 * Note that the context will be expanded with the flags.
 *
 * Returns: The first CompileCommand object which _probably_ has the flags needed to parse fname.
 */
Nullable!CompileCommand findCompileCommandFromIncludes(ref CompileCommandDB compdb,
        FileName fname, ref const CompileCommandFilter flag_filter) {
    import std.algorithm : filter;
    import std.file : exists;
    import std.path : baseName;
    import std.typecons : Yes;

    import cpptooling.analyzer.clang.check_parse_result : hasParseErrors,
        logDiagnostic;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.analyzer.clang.include_visitor;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    string find_file = fname.baseName;

    bool isMatch(string include) {
        return find_file == include.baseName;
    }

    Nullable!CompileCommand r;

    foreach (entry; compdb.filter!(a => exists(a.absoluteFile))) {
        auto flags = entry.parseFlag(flag_filter);
        auto translation_unit = ctx.makeTranslationUnit(entry.absoluteFile, flags);

        if (translation_unit.hasParseErrors) {
            logger.warningf("Skipping '%s' because of compilation errors", entry.absoluteFile);
            logDiagnostic(translation_unit);
        } else if (translation_unit.cursor.hasInclude!isMatch()) {
            r = entry;
            return r;
        }
    }

    return r;
}

struct SearchResult {
    string[] flags;
    AbsolutePath absoluteFile;
}

/// Find flags for fname by searching in the compilation DB.
Nullable!SearchResult findFlags(ref CompileCommandDB compdb, FileName fname,
        const string[] flags, ref const CompileCommandFilter flag_filter) {
    import std.file : exists;
    import std.path : baseName;
    import std.string : join;

    typeof(return) rval;

    auto db_search_result = compdb.appendOrError(flags, fname, flag_filter);
    if (!db_search_result.isNull) {
        rval = SearchResult(db_search_result.cflags, db_search_result.absoluteFile);
        logger.info("Compiler flags: ", rval.flags.join(" "));
        return rval;
    }

    logger.warningf(`Analyzing all files in the compilation DB for one that has an '#include "%s"'`,
            fname.baseName);

    auto sres = compdb.findCompileCommandFromIncludes(fname, flag_filter);
    if (!sres.isNull) {
        logger.info("Using compiler flags from: ", sres.absoluteFile);

        auto p = AbsolutePath(fname);
        if (!exists(p)) {
            logger.warningf("Unable to locate '%s'", p);
            logger.warningf(`Falling back on '%s' because it has an '#include' pulling in the desired file`,
                    sres.absoluteFile);
            p = sres.absoluteFile;
        }

        rval = SearchResult(sres.parseFlag(flag_filter), p);
        // the user may want to see the flags but usually uninterested
        logger.trace("Compiler flags: ", rval.flags.join(" "));
    } else {
        logger.error("Unable to find any compiler flags for: ", fname);
    }

    return rval;
}
