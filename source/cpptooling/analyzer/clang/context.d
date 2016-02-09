// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.context;

import logger = std.experimental.logger;

/// Holds the context of the file.
struct ClangContext {
    import clang.Compiler;
    import clang.Cursor;
    import clang.Index;
    import clang.TranslationUnit;

    /** Initialize context from file
     * Params:
     *  input_file = filename of code to parse
     *  args = extra arguments to pass to libclang
     *  internal_hdr = use internal headers
     */
    this(string input_file, const string[] args = null, bool internal_hdr = true) {
        import std.array : join;

        string[] user_args;
        index = Index(false, false);

        if (internal_hdr) {
            user_args = compilerArgs();
        }

        if (args !is null) {
            user_args = args.dup ~ user_args;
        }

        logger.info("Compiler flags: ", args.join(" "));
        logger.trace("Internal compiler flags: ", user_args);

        // the last argument determines if comments are parsed and therefor
        // accessible in the AST. Default is not.
        translation_unit = TranslationUnit.parse(index, input_file, user_args,
            compiler.extraHeaders);
    }

    ~this() {
        translation_unit.dispose;
        index.dispose;
    }

    /** Top cursor to travers the AST.
     * Return: Cursor of the translation unit
     */
    @property Cursor cursor() {
        return translation_unit.cursor;
    }

private:
    string[] compilerArgs() {
        import std.array : array, join;
        import std.algorithm : map;

        auto compiler_args = compiler.extraIncludePaths.map!(e => "-I" ~ e).array();
        return compiler_args;
    }

    Index index;
    Compiler compiler;
    TranslationUnit translation_unit;
}

/// No errors occured during translation.
bool isValid(ref ClangContext context) {
    return context.translation_unit.isValid;
}

/** Query context for if diagnostic errors where detected during parsing.
 * Return: True if errors where found.
 */
bool hasParseErrors(ref ClangContext context) {
    import deimos.clang.index : CXDiagnosticSeverity;

    if (!context.isValid)
        return true;

    bool has_error = false;
    auto dia = context.translation_unit.diagnostics;
    if (dia.length == 0)
        return false;

    foreach (diag; dia) {
        auto severity = diag.severity;

        final switch (severity) with (CXDiagnosticSeverity) {
        case CXDiagnostic_Ignored:
        case CXDiagnostic_Note:
        case CXDiagnostic_Warning:
            break;
        case CXDiagnostic_Error:
        case CXDiagnostic_Fatal:
            has_error = true;
            break;
        }
    }

    return has_error;
}

/// Log diagnostic error messages to std.logger.
void logDiagnostic(ref ClangContext context) {
    import deimos.clang.index : CXDiagnosticSeverity;

    auto dia = context.translation_unit.diagnostics;

    if (dia.length == 0)
        return;

    foreach (diag; dia) {
        auto severity = diag.severity;

        final switch (severity) with (CXDiagnosticSeverity) {
        case CXDiagnostic_Ignored:
            logger.info(diag.format);
            break;
        case CXDiagnostic_Note:
            logger.info(diag.format);
            break;
        case CXDiagnostic_Warning:
            logger.warning(diag.format);
            break;
        case CXDiagnostic_Error:
            logger.error(diag.format);
            break;
        case CXDiagnostic_Fatal:
            logger.error(diag.format);
            break;
        }
    }
}
