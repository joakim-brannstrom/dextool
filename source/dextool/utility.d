/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.utility;

import logger = std.experimental.logger;

import dextool.type : AbsolutePath, DextoolVersion, ExitStatusType;
import dextool.compilation_db : CompileCommandDB, CompileCommand, orDefaultDb,
    fromFiles;

    @safe:

    enum PreferLang : string {
        none = "",
        c = "-xc",
        cpp = "-xc++"
    }

pure string[] prependDefaultFlags(const string[] in_cflags, const PreferLang lang) {
    import std.algorithm : canFind;

    immutable syntax_only = "-fsyntax-only";
    if (in_cflags.canFind(syntax_only)) {
        return prependLangFlagIfMissing(in_cflags, lang);
    } else {
        return syntax_only ~ prependLangFlagIfMissing(in_cflags, lang);
    }
}

///TODO move to clang module.
pure string[] prependLangFlagIfMissing(in string[] in_cflags, const PreferLang lang) {
    import std.algorithm : findAmong;

    auto v = findAmong(in_cflags, [PreferLang.c, PreferLang.cpp]);

    if (v.length == 0) {
        return [cast(string) lang] ~ in_cflags;
    }

    return in_cflags.dup;
}

@system unittest {
    import test.extra_should : shouldEqualPretty;

    auto cflags = ["-DBEFORE", "-xc++", "-DAND_A_DEFINE", "-I/3906164"];
    cflags.shouldEqualPretty(prependLangFlagIfMissing(cflags, PreferLang.c));
}

/** Apply the visitor on the clang AST derived from the input_file.
 *
 * Params:
 *  input_file = path to a file to analyze
 *  cflags = compiler flags to pass on to clang
 *  visitor = to apply on the clang AST
 *  ctx = $(D ClangContext)
 *
 * Returns: if the analyze was performed ok or errors occured
 */
ExitStatusType analyzeFile(VisitorT, ClangContextT)(const AbsolutePath input_file,
        const string[] cflags, VisitorT visitor, ref ClangContextT ctx) {
    import std.file : exists;

    import cpptooling.analyzer.clang.ast : ClangAST;
    import cpptooling.analyzer.clang.check_parse_result : hasParseErrors,
        logDiagnostic;

    if (!exists(input_file)) {
        logger.errorf("File '%s' do not exist", input_file);
        return ExitStatusType.Errors;
    }

    logger.infof("Analyzing '%s'", input_file);

    auto translation_unit = ctx.makeTranslationUnit(input_file, cflags);
    if (translation_unit.hasParseErrors) {
        logDiagnostic(translation_unit);
        logger.error("Compile error...");
        return ExitStatusType.Errors;
    }

    auto ast = ClangAST!VisitorT(translation_unit.cursor);
    ast.accept(visitor);

    return ExitStatusType.Ok;
}

// this is deprecated
public import dextool.compilation_db : fromArgCompileDb;

/// Version derived from the git archive.
import std.string : strip;

enum dextoolVersion = DextoolVersion(import("version.txt").strip);

static assert(dextoolVersion.length > 0, "Failed to import version.txt at compile time");
