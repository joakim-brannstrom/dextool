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

import dextool.type : AbsolutePath, FileName;

void tokenMutate(const AbsolutePath input_file, const AbsolutePath output_dir, const string[] cflags) {
    import std.random : uniform;
    import std.file : exists;
    import std.typecons : Yes;

    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.analyzer.clang.ast : ClangAST;
    import cpptooling.analyzer.clang.check_parse_result : hasParseErrors,
        logDiagnostic;

    if (!exists(input_file)) {
        logger.errorf("File '%s' do not exist", input_file);
        return;
    }

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    logger.infof("Mutating '%s'", input_file);

    auto translation_unit = ctx.makeTranslationUnit(input_file, cflags);
    if (translation_unit.hasParseErrors) {
        logDiagnostic(translation_unit);
        logger.error("Compile error...");
        return;
    }

    auto tu_c = translation_unit.cursor;
    auto tokens = tu_c.tokens;
    auto drop_token = uniform(0, tokens.length);

    logger.info("Total number of mutation points: ", tokens.length);
    logger.info("dropping token: ", drop_token);

    // remove the token from the source code

    auto source_range = tokens[drop_token].extent;
    logger.info("location: ", source_range);

    import dextool.plugin.mutate.backend.vfs;

    auto offset = Offset(source_range.start.spelling.offset, source_range.end.spelling.offset);

    import std.algorithm : each;
    import std.stdio : File;
    import std.path : buildPath, baseName;

    auto fout = File(buildPath(output_dir, input_file.baseName), "w");
    ctx.virtualFileSystem.drop!(void[])(input_file, offset).each!(a => fout.rawWrite(a));
}
