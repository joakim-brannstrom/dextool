/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.utility;

public import std.typecons : Yes, No;

public import scriptlike;
public import unit_threaded;

public import dextool_test;
public import dextool_test.config;

immutable defaultDb = "database.sqlite3";

auto makeDextool(const ref TestEnv env) {
    // dfmt off
    return dextool_test.makeDextool(env)
        .args(["mutate"])
        .addArg(["--db", (env.outdir ~ defaultDb).toString])
        .addArg("--dry-run")
        .addArg(["--mutant-order", "consecutive"])
        .addArg(["--mutant-compile", "/bin/true"])
        .addArg(["--mutant-test", "/bin/true"])
        .addArg(["--mutant-test-runtime", "10000"]);
    // dfmt on
}

auto makeDextoolReport(const ref TestEnv env, Path test_data) {
    // dfmt off
    return dextool_test.makeDextool(env)
        .args(["mutate"])
        .addArg(["--db", (env.outdir ~ defaultDb).toString])
        .setWorkdir(test_data.toString)
        .addArg(["--restrict", test_data.toString])
        .addArg(["--mode", "report"]);
    // dfmt on
}

auto makeCompile(const ref TestEnv env, Path srcdir) {
    return dextool_test.makeCompile(env, "g++").addInclude(srcdir).outputToDefaultBinary;
}

auto readOutput(const ref TestEnv testEnv, string fname) {
    return std.file.readText((testEnv.outdir ~ fname).toString).splitLines.array();
}

struct SubStr {
    string key;

    bool opEquals(const string rhs) const {
        import std.string : indexOf;

        return rhs.indexOf(key) != -1;
    }
}

import std.range : isInputRange;

/** Make a `SubSeq` by constructing a range of `ElementType` from `T1`.
 *
 * Params:
 *  ElementType = the element type to convert `T1` to.
 */
auto makeSubSeq(ElementType, T1)(T1 seq, in string file = __FILE__, in size_t line = __LINE__) {
    import std.algorithm : map;

    auto r = seq.map!(a => ElementType(a));
    return SubSeq!(typeof(r))(r, file, line);
}

/** Make a `SubSeq` by using the range `T`.
 */
auto makeSubSeq(T)(T seq, in string file = __FILE__, in size_t line = __LINE__)
        if (isInputRange!T) {
    return SubSeq!T(seq, file, line);
}

/** Test that a sequence of sub-elements are found in the container in consecutive order.
 */
struct SubSeq(SeqT) {
    import std.algorithm : map;

    private {
        SeqT seq;
        size_t next;
        string file;
        size_t line;
    }

    /**
     * Params:
     *  seq = sequence of elements to verify
     */
    this(InT)(InT seq, in string file = __FILE__, in size_t line = __LINE__)
            if (isInputRange!InT) {
        import std.array : array;

        this.seq = seq;
        this.file = file;
        this.line = line;
    }

    ~this() {
        import std.format : format;

        if (seq.length != next) {
            throw new UnitTestException(format("Expected substrings left %s:\n%(%s\n%)",
                    seq.length - next, seq[next .. $]), file, line);
        }
    }

    void shouldBeIn(T)(T in_seq) if (isInputRange!T) {
        foreach (const s; in_seq) {
            if (next < seq.length && seq[next] == s) {
                ++next;
            }
        }
    }
}
