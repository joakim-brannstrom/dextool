/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.utility;

import std.regex : Regex;
import std.stdio : File;
import std.typecons : Unique, Nullable, NullableRef;
import logger = std.experimental.logger;

import application.types;
import application.compilation_db;

///TODO don't catch Exception, catch the specific.
auto tryOpenFile(string filename, string mode) @trusted {
    import std.exception;
    import std.typecons : Unique;

    Unique!File rval;

    try {
        rval = Unique!File(new File(filename, mode));
    }
    catch (Exception ex) {
    }
    if (rval.isEmpty) {
        try {
            logger.errorf("Unable to read/write file '%s'", filename);
        }
        catch (Exception ex) {
        }
    }

    return rval;
}

///TODO don't catch Exception, catch the specific.
auto tryWriting(string fname, string data) @trusted nothrow {
    import std.exception;

    static auto action(string fname, string data) {
        auto f = tryOpenFile(fname, "w");

        if (f.isEmpty) {
            return ExitStatusType.Errors;
        }
        scope (exit)
            f.close();

        f.write(data);

        return ExitStatusType.Ok;
    }

    auto status = ExitStatusType.Errors;

    try {
        status = action(fname, data);
    }
    catch (Exception ex) {
    }

    try {
        final switch (status) with (ExitStatusType) {
        case Ok:
            break;
        case Errors:
            logger.error("Failed to write to file ", fname);
            break;
        }
    }
    catch (Exception ex) {
    }

    return status;
}

auto prependDefaultFlags(in string[] in_cflags, in string prefer_lang) {
    return "-fsyntax-only" ~ prependLangFlagIfMissing(in_cflags, prefer_lang);
}

///TODO move to clang module.
auto prependLangFlagIfMissing(in string[] in_cflags, in string prefer_lang) {
    import std.algorithm : findAmong;

    auto v = findAmong(in_cflags, ["-xc", "-xc++"]);

    if (v.length == 0) {
        return [prefer_lang] ~ in_cflags;
    }

    return in_cflags.dup;
}

unittest {
    import test.extra_should : shouldEqualPretty;

    auto cflags = ["-DBEFORE", "-xc++", "-DAND_A_DEFINE", "-I/3906164"];
    cflags.shouldEqualPretty(prependLangFlagIfMissing(cflags, "-xc"));
}

/** if no regexp or no match when using the regexp, using the include
 * path as-is.
 */
FileName stripFile(FileName fname, Regex!char re) @trusted {
    import std.array : appender;
    import std.algorithm : copy;
    import std.range : dropOne;
    import std.regex : matchFirst;

    if (re.empty) {
        return fname;
    }

    auto c = matchFirst(cast(string) fname, re);
    auto rval = fname;

    debug logger.tracef("input is '%s'. After strip: %s", fname, c);

    if (!c.empty) {
        auto app = appender!string();
        c.dropOne.copy(app);
        rval = FileName(app.data);
    }

    return rval;
}

/** Fixup the includes to be ready for usage as #include.
 *
 * Deduplicate.
 * Strip the includes according to the user supplied configuration.
 */
auto stripIncl(ref FileName[] incls, Regex!char re) {
    import std.array : array;
    import std.algorithm : cache, map, filter;
    import cpptooling.utility : dedup;

    // dfmt off
    auto r = dedup(incls)
        .map!(a => stripFile(a, re))
        .filter!(a => a.length > 0)
        .array();
    // dfmt on

    return r;
}

/** Includes intended for the test double.
 *
 * Filtered according to the user.
 *
 * TODO change to using a RedBlackTree to avoid duplications of files.
 *
 * States:
 *  - Normal.
 *      Start state.
 *      File are accepted and stored in buffer.
 *      Important that transitions FROM this state clears the internal buffer.
 *      Rational: The other states override data that was gathered during
 *      Normal.
 *  - HaveRoot.
 *      One or more roots have been found.
 *      Replaces all "Normal".
 *  - UserDefined.
 *      The user have supplied a list of includes which override any detected.
 */
struct TestDoubleIncludes {
    import std.regex;

    enum State {
        Normal,
        HaveRoot,
        UserDefined
    }

    FileName[] incls;
    State st;
    Regex!char strip_incl;
    private FileName[] unstripped_incls;

    @disable this();

    this(Regex!char strip_incl) {
        this.strip_incl = strip_incl;
    }

    /** Replace buffer of includes with argument.
     *
     * See description of states to understand what UserDefined entitles.
     */
    void forceIncludes(string[] in_incls) {
        st = State.UserDefined;
        foreach (incl; in_incls) {
            incls ~= FileName(incl);
        }
    }

    /// Assuming user defined includes are good as they are so no stripping.
    void doStrip() @safe {
        switch (st) with (State) {
        case Normal:
        case HaveRoot:
            incls = stripIncl(unstripped_incls, strip_incl);
            break;
        default:
        }
    }

    void put(FileName fname, LocationType type) @safe
    in {
        import std.utf : validate;

        validate((cast(string) fname));
    }
    body {
        final switch (st) with (State) {
        case Normal:
            if (type == LocationType.Root) {
                unstripped_incls = [fname];
                st = HaveRoot;
            } else {
                unstripped_incls ~= fname;
            }
            break;
        case HaveRoot:
            // only accepting roots
            if (type == LocationType.Root) {
                unstripped_incls ~= fname;
            }
            break;
        case UserDefined:
            // ignoring includes
            break;
        }
    }

    string toString() @safe const {
        import std.exception : assumeUnique;

        char[] buf;
        buf.reserve(100);
        this.toString((const(char)[] s) { buf ~= s; });
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    void toString(Writer)(scope Writer w) const {
        import std.algorithm : copy, joiner, map;
        import std.ascii : newline;
        import std.conv : to;
        import std.range : chain, only;
        import std.range.primitives : put;

        chain(only(st.to!string()), incls.map!(a => cast(string) a),
                unstripped_incls.map!(a => cast(string) a)).joiner(newline).copy(w);
    }
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
ExitStatusType analyzeFile(VisitorT, ClangContextT)(in string input_file,
        in string[] cflags, VisitorT visitor, ref ClangContextT ctx) {
    import std.file : exists;

    import cpptooling.analyzer.clang.ast : ClangAST;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.analyzer.clang.utility : hasParseErrors, logDiagnostic;

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

ExitStatusType writeFileData(T)(ref T data) {
    foreach (p; data) {
        auto status = tryWriting(cast(string) p.filename, p.data);
        if (status != ExitStatusType.Ok) {
            return ExitStatusType.Errors;
        }
    }

    return ExitStatusType.Ok;
}

CompileCommandDB fromArgCompileDb(string[] paths) {
    import std.array : appender;

    auto app = appender!(CompileCommand[])();
    paths.orDefaultDb.fromFiles(app);

    return CompileCommandDB(app.data);
}

/// Version derived from the git archive.
enum dextoolVersion = DextoolVersion(import("version.txt"));

static assert(dextoolVersion.length > 0, "Failed to import version.txt at compile time");
