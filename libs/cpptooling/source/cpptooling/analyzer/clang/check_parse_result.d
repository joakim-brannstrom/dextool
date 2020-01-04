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
bool hasParseErrors(ref TranslationUnit tu) @safe {
    import clang.c.Index : CXDiagnosticSeverity;

    if (!tu.isValid)
        return true;

    auto dia = tu.diagnostics;

    auto rval = () @trusted {
        foreach (diag; dia) {
            auto severity = diag.severity;

            final switch (severity) with (CXDiagnosticSeverity) {
            case ignored:
            case note:
            case warning:
                break;
            case error:
            case fatal:
                return true;
            }
        }
        return false;
    }();

    return rval;
}

/** Log diagnostic error messages to std.logger.
 *
 * TODO Change to a template with a sink as parameter.
 */
void logDiagnostic(ref TranslationUnit tu) @safe {
    import logger = std.experimental.logger;

    import clang.c.Index : CXDiagnosticSeverity;

    auto dia = tu.diagnostics;

    () @trusted {
        foreach (diag; dia) {
            auto severity = diag.severity;

            final switch (severity) with (CXDiagnosticSeverity) {
            case ignored:
                logger.info(diag.format);
                break;
            case note:
                logger.info(diag.format);
                break;
            case warning:
                logger.warning(diag.format);
                break;
            case error:
                logger.error(diag.format);
                break;
            case fatal:
                logger.error(diag.format);
                break;
            }
        }
    }();
}
