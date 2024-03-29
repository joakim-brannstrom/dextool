/*===-- clang-c/CXDiagnostic.h - C Index Diagnostics --------------*- C -*-===*\
|*                                                                            *|
|* Part of the LLVM Project, under the Apache License v2.0 with LLVM          *|
|* Exceptions.                                                                *|
|* See https://llvm.org/LICENSE.txt for license information.                  *|
|* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception                    *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This header provides the interface to C Index diagnostics.                 *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

module clang.c.CXDiagnostic;

public import clang.c.CXSourceLocation;
public import clang.c.CXString;

extern (C):

/**
 * \defgroup CINDEX_DIAG Diagnostic reporting
 *
 * @{
 */

/**
 * Describes the severity of a particular diagnostic.
 */
enum CXDiagnosticSeverity
{
    /**
     * A diagnostic that has been suppressed, e.g., by a command-line
     * option.
     */
    ignored = 0,

    /**
     * This diagnostic is a note that should be attached to the
     * previous (non-note) diagnostic.
     */
    note = 1,

    /**
     * This diagnostic indicates suspicious code that may not be
     * wrong.
     */
    warning = 2,

    /**
     * This diagnostic indicates that the code is ill-formed.
     */
    error = 3,

    /**
     * This diagnostic indicates that the code is ill-formed such
     * that future parser recovery is unlikely to produce useful
     * results.
     */
    fatal = 4
}

/**
 * A single diagnostic, containing the diagnostic's severity,
 * location, text, source ranges, and fix-it hints.
 */
alias CXDiagnostic = void*;

/**
 * A group of CXDiagnostics.
 */
alias CXDiagnosticSet = void*;

/**
 * Determine the number of diagnostics in a CXDiagnosticSet.
 */
uint clang_getNumDiagnosticsInSet(CXDiagnosticSet Diags);

/**
 * Retrieve a diagnostic associated with the given CXDiagnosticSet.
 *
 * \param Diags the CXDiagnosticSet to query.
 * \param Index the zero-based diagnostic number to retrieve.
 *
 * \returns the requested diagnostic. This diagnostic must be freed
 * via a call to \c clang_disposeDiagnostic().
 */
CXDiagnostic clang_getDiagnosticInSet(CXDiagnosticSet Diags, uint Index);

/**
 * Describes the kind of error that occurred (if any) in a call to
 * \c clang_loadDiagnostics.
 */
enum CXLoadDiag_Error
{
    /**
     * Indicates that no error occurred.
     */
    none = 0,

    /**
     * Indicates that an unknown error occurred while attempting to
     * deserialize diagnostics.
     */
    unknown = 1,

    /**
     * Indicates that the file containing the serialized diagnostics
     * could not be opened.
     */
    cannotLoad = 2,

    /**
     * Indicates that the serialized diagnostics file is invalid or
     * corrupt.
     */
    invalidFile = 3
}

/**
 * Deserialize a set of diagnostics from a Clang diagnostics bitcode
 * file.
 *
 * \param file The name of the file to deserialize.
 * \param error A pointer to a enum value recording if there was a problem
 *        deserializing the diagnostics.
 * \param errorString A pointer to a CXString for recording the error string
 *        if the file was not successfully loaded.
 *
 * \returns A loaded CXDiagnosticSet if successful, and NULL otherwise.  These
 * diagnostics should be released using clang_disposeDiagnosticSet().
 */
CXDiagnosticSet clang_loadDiagnostics(
    const(char)* file,
    CXLoadDiag_Error* error,
    CXString* errorString);

/**
 * Release a CXDiagnosticSet and all of its contained diagnostics.
 */
void clang_disposeDiagnosticSet(CXDiagnosticSet Diags);

/**
 * Retrieve the child diagnostics of a CXDiagnostic.
 *
 * This CXDiagnosticSet does not need to be released by
 * clang_disposeDiagnosticSet.
 */
CXDiagnosticSet clang_getChildDiagnostics(CXDiagnostic D);

/**
 * Destroy a diagnostic.
 */
void clang_disposeDiagnostic(CXDiagnostic Diagnostic);

/**
 * Options to control the display of diagnostics.
 *
 * The values in this enum are meant to be combined to customize the
 * behavior of \c clang_formatDiagnostic().
 */
enum CXDiagnosticDisplayOptions
{
    /**
     * Display the source-location information where the
     * diagnostic was located.
     *
     * When set, diagnostics will be prefixed by the file, line, and
     * (optionally) column to which the diagnostic refers. For example,
     *
     * \code
     * test.c:28: warning: extra tokens at end of #endif directive
     * \endcode
     *
     * This option corresponds to the clang flag \c -fshow-source-location.
     */
    displaySourceLocation = 0x01,

    /**
     * If displaying the source-location information of the
     * diagnostic, also include the column number.
     *
     * This option corresponds to the clang flag \c -fshow-column.
     */
    displayColumn = 0x02,

    /**
     * If displaying the source-location information of the
     * diagnostic, also include information about source ranges in a
     * machine-parsable format.
     *
     * This option corresponds to the clang flag
     * \c -fdiagnostics-print-source-range-info.
     */
    displaySourceRanges = 0x04,

    /**
     * Display the option name associated with this diagnostic, if any.
     *
     * The option name displayed (e.g., -Wconversion) will be placed in brackets
     * after the diagnostic text. This option corresponds to the clang flag
     * \c -fdiagnostics-show-option.
     */
    displayOption = 0x08,

    /**
     * Display the category number associated with this diagnostic, if any.
     *
     * The category number is displayed within brackets after the diagnostic text.
     * This option corresponds to the clang flag
     * \c -fdiagnostics-show-category=id.
     */
    displayCategoryId = 0x10,

    /**
     * Display the category name associated with this diagnostic, if any.
     *
     * The category name is displayed within brackets after the diagnostic text.
     * This option corresponds to the clang flag
     * \c -fdiagnostics-show-category=name.
     */
    displayCategoryName = 0x20
}

/**
 * Format the given diagnostic in a manner that is suitable for display.
 *
 * This routine will format the given diagnostic to a string, rendering
 * the diagnostic according to the various options given. The
 * \c clang_defaultDiagnosticDisplayOptions() function returns the set of
 * options that most closely mimics the behavior of the clang compiler.
 *
 * \param Diagnostic The diagnostic to print.
 *
 * \param Options A set of options that control the diagnostic display,
 * created by combining \c CXDiagnosticDisplayOptions values.
 *
 * \returns A new string containing for formatted diagnostic.
 */
CXString clang_formatDiagnostic(CXDiagnostic Diagnostic, uint Options);

/**
 * Retrieve the set of display options most similar to the
 * default behavior of the clang compiler.
 *
 * \returns A set of display options suitable for use with \c
 * clang_formatDiagnostic().
 */
uint clang_defaultDiagnosticDisplayOptions();

/**
 * Determine the severity of the given diagnostic.
 */
CXDiagnosticSeverity clang_getDiagnosticSeverity(CXDiagnostic);

/**
 * Retrieve the source location of the given diagnostic.
 *
 * This location is where Clang would print the caret ('^') when
 * displaying the diagnostic on the command line.
 */
CXSourceLocation clang_getDiagnosticLocation(CXDiagnostic);

/**
 * Retrieve the text of the given diagnostic.
 */
CXString clang_getDiagnosticSpelling(CXDiagnostic);

/**
 * Retrieve the name of the command-line option that enabled this
 * diagnostic.
 *
 * \param Diag The diagnostic to be queried.
 *
 * \param Disable If non-NULL, will be set to the option that disables this
 * diagnostic (if any).
 *
 * \returns A string that contains the command-line option used to enable this
 * warning, such as "-Wconversion" or "-pedantic".
 */
CXString clang_getDiagnosticOption(CXDiagnostic Diag, CXString* Disable);

/**
 * Retrieve the category number for this diagnostic.
 *
 * Diagnostics can be categorized into groups along with other, related
 * diagnostics (e.g., diagnostics under the same warning flag). This routine
 * retrieves the category number for the given diagnostic.
 *
 * \returns The number of the category that contains this diagnostic, or zero
 * if this diagnostic is uncategorized.
 */
uint clang_getDiagnosticCategory(CXDiagnostic);

/**
 * Retrieve the name of a particular diagnostic category.  This
 *  is now deprecated.  Use clang_getDiagnosticCategoryText()
 *  instead.
 *
 * \param Category A diagnostic category number, as returned by
 * \c clang_getDiagnosticCategory().
 *
 * \returns The name of the given diagnostic category.
 */
CXString clang_getDiagnosticCategoryName(uint Category);

/**
 * Retrieve the diagnostic category text for a given diagnostic.
 *
 * \returns The text of the given diagnostic category.
 */
CXString clang_getDiagnosticCategoryText(CXDiagnostic);

/**
 * Determine the number of source ranges associated with the given
 * diagnostic.
 */
uint clang_getDiagnosticNumRanges(CXDiagnostic);

/**
 * Retrieve a source range associated with the diagnostic.
 *
 * A diagnostic's source ranges highlight important elements in the source
 * code. On the command line, Clang displays source ranges by
 * underlining them with '~' characters.
 *
 * \param Diagnostic the diagnostic whose range is being extracted.
 *
 * \param Range the zero-based index specifying which range to
 *
 * \returns the requested source range.
 */
CXSourceRange clang_getDiagnosticRange(CXDiagnostic Diagnostic, uint Range);

/**
 * Determine the number of fix-it hints associated with the
 * given diagnostic.
 */
uint clang_getDiagnosticNumFixIts(CXDiagnostic Diagnostic);

/**
 * Retrieve the replacement information for a given fix-it.
 *
 * Fix-its are described in terms of a source range whose contents
 * should be replaced by a string. This approach generalizes over
 * three kinds of operations: removal of source code (the range covers
 * the code to be removed and the replacement string is empty),
 * replacement of source code (the range covers the code to be
 * replaced and the replacement string provides the new code), and
 * insertion (both the start and end of the range point at the
 * insertion location, and the replacement string provides the text to
 * insert).
 *
 * \param Diagnostic The diagnostic whose fix-its are being queried.
 *
 * \param FixIt The zero-based index of the fix-it.
 *
 * \param ReplacementRange The source range whose contents will be
 * replaced with the returned replacement string. Note that source
 * ranges are half-open ranges [a, b), so the source code should be
 * replaced from a and up to (but not including) b.
 *
 * \returns A string containing text that should be replace the source
 * code indicated by the \c ReplacementRange.
 */
CXString clang_getDiagnosticFixIt(
    CXDiagnostic Diagnostic,
    uint FixIt,
    CXSourceRange* ReplacementRange);

/**
 * @}
 */

