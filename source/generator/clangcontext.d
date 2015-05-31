/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.clangcontext;

import std.ascii;
import std.array;
import std.conv;
import std.stdio;
import std.string;
import std.typecons;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Compiler;
import clang.Cursor;
import clang.Index;
import clang.Token;
import clang.TranslationUnit;
import clang.Visitor;

import dsrcgen.cpp;

/// Holds the context of the file.
class ClangContext {
    /** Initialize context from file
     * Params:
     *  input_file_ = filename of code to parse
     *  args = extra arguments to pass to libclang
     */
    this(string input_file_, const string[] args = null) {
        input_file = input_file_;
        index = Index(false, false);

        if (args !is null) {
            // skip logging of the internal includes (compiler_args) as to not confuse the user.
            user_args = args.idup;
            logger.infof("Compiler flags: %s %s", base_args.join(" "), user_args.join(" "));
        }

        // the last argument determines if comments are parsed and therefor
        // accessible in the AST. Default is not.
        translation_unit = TranslationUnit.parse(index, input_file,
            compilerArgs, compiler.extraHeaders);
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
        return base_args ~ compiler_args ~ user_args;
    }

    static const string[] base_args = ["-xc++"];
    string input_file;
    Index index;
    TranslationUnit translation_unit;
    Compiler compiler;
    immutable string[] user_args;
}

/// No errors occured during translation.
bool isValid(ClangContext context) {
    return context.translation_unit.isValid;
}

/** Query context for if diagnostic errors where detected during parsing.
 * Return: True if errors where found.
 */
bool hasParseErrors(ClangContext context) {
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
void logDiagnostic(ClangContext context) {
    if (!context.isValid)
        return;

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
