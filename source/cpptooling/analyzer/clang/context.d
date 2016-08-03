// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.context;

import std.typecons : Flag, Yes;

import logger = std.experimental.logger;

/// Holds the context of the file.
struct ClangContext {
    import clang.Compiler;
    import clang.Cursor;
    import clang.Index;
    import clang.TranslationUnit;

    alias MakeTU = TranslationUnit delegate(ref ClangContext ctx);

    /** Initialize context from in-memory source code.
     * Params:
     *  content = in-memory content that is handed over to clang for parsing
     *  args = extra arguments to pass to libclang
     *
     * Returns: ClangContext
     */
    static auto fromString(string content, const(string[]) args = null) {
        return ClangContext((ref ClangContext ctx) {
            auto use_args = ctx.makeArgs(args, Yes.useInternalHeaders);
            return TranslationUnit.parseString(ctx.index, content, use_args,
                ctx.compiler.extraHeaders);
        });
    }

    /** Initialize context from file.
     * Params:
     *  input_file = filename of the source code that is handed over to clang for parsing
     *  args = extra arguments to pass to libclang
     *
     * Returns: ClangContext
     */
    static auto fromFile(string input_file, const(string[]) args = null) {
        return ClangContext((ref ClangContext ctx) {
            auto use_args = ctx.makeArgs(args, Yes.useInternalHeaders);
            return TranslationUnit.parse(ctx.index, input_file, use_args,
                ctx.compiler.extraHeaders);
        });
    }

    /** Deferred construction of the context.
     *
     * The logic for constructing the translation unit is split to a delegate.
     *
     * The split is to enables a design where the context initializes the basic
     * memory structure like Compiler and Index without handling the logic of
     * constructing the translation unit.
     *
     * Params:
     *   makeTranslationUnit = construct a translation unit
     */
    private this(MakeTU makeTranslationUnit) {
        index = Index(false, false);
        translation_unit = makeTranslationUnit(this);
    }

    /** Top cursor to travers the AST.
     * Returns: Cursor of the translation unit
     */
    @property Cursor cursor() {
        return translation_unit.cursor;
    }

    /// Returns: The translation unit for the context
    TranslationUnit translationUnit() {
        return translation_unit;
    }

private:
    string[] makeArgs(const(string[]) args, Flag!"useInternalHeaders" internal_hdr) {
        import std.array : join;

        string[] use_args;

        if (internal_hdr) {
            use_args = compilerArgs();
        }

        if (args !is null) {
            use_args = args.dup ~ use_args;
        }

        logger.info("Compiler flags: ", args.join(" "));
        logger.trace("Internal compiler flags: ", use_args.join(" "));

        return use_args;
    }

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
