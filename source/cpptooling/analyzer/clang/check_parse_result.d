/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.check_parse_result;

import clang.TranslationUnit : TranslationUnit;

/** Check the context for diagnositc errors.
 *
 * Returns: True if errors where found.
 */
bool hasParseErrors(ref TranslationUnit tu) {
    import deimos.clang.index : CXDiagnosticSeverity;

    if (!tu.isValid)
        return true;

    auto dia = tu.diagnostics;

    foreach (diag; dia) {
        auto severity = diag.severity;

        final switch (severity) with (CXDiagnosticSeverity) {
        case CXDiagnostic_Ignored:
        case CXDiagnostic_Note:
        case CXDiagnostic_Warning:
            break;
        case CXDiagnostic_Error:
        case CXDiagnostic_Fatal:
            return true;
        }
    }

    return false;
}

/** Log diagnostic error messages to std.logger.
 *
 * TODO Change to a template with a sink as parameter.
 */
void logDiagnostic(ref TranslationUnit tu) {
    import logger = std.experimental.logger;

    import deimos.clang.index : CXDiagnosticSeverity;

    auto dia = tu.diagnostics;

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
