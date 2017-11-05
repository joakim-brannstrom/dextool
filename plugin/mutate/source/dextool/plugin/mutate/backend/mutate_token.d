/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains a token mutator.
*/
module dextool.plugin.mutate.backend.mutate_token;

import logger = std.experimental.logger;
import std.typecons : Nullable;

import dextool.type : AbsolutePath, FileName, Exists;

@safe:

/**
 *
 * Params:
 *  input_file =
 */
void tokenMutate(const Exists!AbsolutePath input_file, const AbsolutePath output_dir,
        const string[] cflags, const Nullable!size_t mutation_point) {
    import std.random : uniform;
    import std.typecons : Yes;

    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.analyzer.clang.ast : ClangAST;
    import cpptooling.analyzer.clang.check_parse_result : hasParseErrors,
        logDiagnostic;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    logger.infof("Mutating '%s'", input_file);

    auto translation_unit = ctx.makeTranslationUnit(input_file, cflags);
    if (translation_unit.hasParseErrors) {
        logDiagnostic(translation_unit);
        logger.error("Compile error...");
        return;
    }

    auto tu_c = translation_unit.cursor;
    size_t drop_token;

    // trusted: no references to the tokens escape the delegate.
    auto findTokenRange() @trusted {
        auto tokens = tu_c.tokens;

        if (mutation_point.isNull || mutation_point >= tokens.length)
            drop_token = uniform(0, tokens.length);

        logger.info("Total number of mutation points: ", tokens.length);
        logger.info("dropping token: ", drop_token);

        // remove the token from the source code

        auto source_range = tokens[drop_token].extent;
        logger.info("location: ", source_range);

        return source_range;
    }

    auto source_range = findTokenRange();

    import dextool.plugin.mutate.backend.vfs;

    auto offset = Offset(source_range.start.spelling.offset, source_range.end.spelling.offset);

    import std.algorithm : each;
    import std.stdio : File;
    import std.path : buildPath, baseName;

    auto s = ctx.virtualFileSystem.drop!(void[])(input_file, offset);
    auto fout = File(buildPath(output_dir, input_file.baseName), "w");
    // trusted: is safe in dmd-2.077.0. Remove trusted in the future
    () @trusted{ s.each!(a => fout.rawWrite(a)); }();
}
