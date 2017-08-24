/**
Copyright: Copyright (c) 2011-2016 Jacob Carlborg. All rights reserved.
Authors: Jacob Carlborg, Joakim Brännström (joakim.brannstrom dottli gmx.com)
Version: 1.1+
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)

History:
  1.0 initial release. 2011$(BR)
    Jacob Carlborg
  1.1+ additional documentation
    Joakim Brännström
*/
module clang.Index;

import deimos.clang.index;

/** An "index" that consists of a set of translation units that would typically
 * be linked together into an executable or library.
 *
 * Provides a shared context for creating translation units.
 *
 * It provides two options:
 *
 * - excludeDeclarationsFromPCH: When non-zero, allows enumeration of "local"
 * declarations (when loading any new translation units). A "local" declaration
 * is one that belongs in the translation unit itself and not in a precompiled
 * header that was used by the translation unit. If zero, all declarations
 * will be enumerated.
 *
 * Here is an example:
 *
 * Example:
 * ---
 *   // excludeDeclsFromPCH = 1, displayDiagnostics=1
 *   Idx = clang_createIndex(1, 1);
 *
 *   // IndexTest.pch was produced with the following command:
 *   // "clang -x c IndexTest.h -emit-ast -o IndexTest.pch"
 *   TU = clang_createTranslationUnit(Idx, "IndexTest.pch");
 *
 *   // This will load all the symbols from 'IndexTest.pch'
 *   clang_visitChildren(clang_getTranslationUnitCursor(TU),
 *                       TranslationUnitVisitor, 0);
 *   clang_disposeTranslationUnit(TU);
 *
 *   // This will load all the symbols from 'IndexTest.c', excluding symbols
 *   // from 'IndexTest.pch'.
 *   char *args[] = { "-Xclang", "-include-pch=IndexTest.pch" };
 *   TU = clang_createTranslationUnitFromSourceFile(Idx, "IndexTest.c", 2, args,
 *                                                  0, 0);
 *   clang_visitChildren(clang_getTranslationUnitCursor(TU),
 *                       TranslationUnitVisitor, 0);
 *   clang_disposeTranslationUnit(TU);
 * ---
 *
 * This process of creating the 'pch', loading it separately, and using it (via
 * -include-pch) allows 'excludeDeclsFromPCH' to remove redundant callbacks
 * (which gives the indexer the same performance benefit as the compiler).
 */
struct Index {
    import clang.Util;

    static private struct ContainIndex {
        mixin CX!("Index");

        ~this() @safe {
            dispose();
        }
    }

    ContainIndex cx;
    alias cx this;

    @disable this(this);

    this(bool excludeDeclarationsFromPCH, bool displayDiagnostics) @trusted {
        cx = ContainIndex(clang_createIndex(excludeDeclarationsFromPCH ? 1 : 0,
                displayDiagnostics ? 1 : 0));
    }
}
