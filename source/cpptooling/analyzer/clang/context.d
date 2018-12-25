/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.context;

import std.typecons : Flag;
import logger = std.experimental.logger;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
}

@safe:

/** Convenient context of items needed to practically create a clang AST.
 *
 * "Creating a clang AST" means calling $(D makeTranslationUnit).
 *
 * Assumes that the scope of a ClangContext is the same as that stated for a
 * clang Index. Namely that those translation units that are created are the
 * same as those that would be linked together into an executable or library.
 *
 * Items are:
 *  - An index that all translation units use as input.
 *  - A VFS providing access to the files that the translation unites are
 *    derived from.
 */
struct ClangContext {
    import clang.Index : Index;
    import clang.TranslationUnit : TranslationUnit;

    import cpptooling.utility.virtualfilesystem : VirtualFileSystem, FileName;

    import clang.c.Index : CXTranslationUnit_Flags;

    private {
        Index index;
        string[] internal_header_arg;
        string[] syntax_only_arg;
    }

    /** Access to the virtual filesystem used when instantiating translation
     * units.
     *
     * Note:
     * NOT using the abbreviation VFS because it is not commonly known. Better
     * to be specific.
     */
    VirtualFileSystem virtualFileSystem;

    @disable this();

    // The context is "heavy" therefor disabling moving.
    @disable this(this);

    /** Create an instance.
     *
     * The binary dextool has clang specified headers attached. Those are feed
     * to the VFS and used when the flag useInternalHeaders is "yes". To make
     * them accessable a "-I" parameter with their in-memory location is
     * supplied to all instantiated translation units.
     *
     * TODO from llvm-6.0 -fsyntax-only is default and ignored. The
     * functionality to prepend with -fsyntax-only should thus be removed.
     *
     * Params:
     *   useInternalHeaders = load the VFS with in-memory system headers.
     *   prependParamSyntaxOnly = prepend the flag -fsyntax-only to instantiated translation units.
     */
    this(Flag!"useInternalHeaders" useInternalHeaders,
            Flag!"prependParamSyntaxOnly" prependParamSyntaxOnly) @trusted {
        this.index = Index(false, false);
        this.virtualFileSystem = VirtualFileSystem();

        if (useInternalHeaders) {
            import cpptooling.utility.virtualfilesystem : FileName;
            import clang.Compiler : Compiler;

            Compiler compiler;
            this.internal_header_arg = compiler.extraIncludeFlags;
            foreach (hdr; compiler.extraHeaders) {
                auto f = virtualFileSystem.openInMemory(hdr.filename.FileName);
                f.write(hdr.content);
            }
        }

        if (prependParamSyntaxOnly) {
            this.syntax_only_arg = ["-fsyntax-only"];
        }
    }

    /** Create a translation unit from the context.
     *
     * The translation unit is NOT kept by the context.
     */
    auto makeTranslationUnit(in string sourceFilename, in string[] commandLineArgs = null,
            uint options = CXTranslationUnit_Flags.detailedPreprocessingRecord) @safe {
        import std.array : join;

        auto prependDefaultFlags(string[] in_cflags) {
            import std.algorithm : canFind;

            if (in_cflags.canFind(syntax_only_arg)) {
                return in_cflags;
            } else {
                return syntax_only_arg ~ in_cflags;
            }
        }

        debug logger.trace(sourceFilename);
        debug logger.trace("Compiler flags: ", commandLineArgs.join(" "));

        string[] args = prependDefaultFlags(commandLineArgs ~ internal_header_arg);

        debug logger.trace("Internal compiler flags: ", args.join(" "));

        // ensure the file exist in the filesys layer.
        // it has either been added as an in-memory file by the user or it is
        // read from the filesystem.
        virtualFileSystem.open(cast(FileName) sourceFilename);

        import cpptooling.utility.virtualfilesystem : toClangFiles;

        auto files = virtualFileSystem.toClangFiles;

        return TranslationUnit.parse(index, sourceFilename, args, files);
    }
}

@("shall be an instance")
@system unittest {
    import std.typecons : Yes;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
}
