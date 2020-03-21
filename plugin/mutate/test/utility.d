/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.utility;

import std.string : splitLines;

public import logger = std.experimental.logger;
public import std.typecons : Yes, No;

public import unit_threaded;

public import dextool_test;
public import dextool_test.config;

auto makeDextoolAnalyze(const ref TestEnv env) {
    // dfmt off
    return dextool_test.makeDextool(env)
        .setWorkdir(workDir)
        .args(["mutate", "analyze"])
        .addPostArg(["--db", (env.outdir ~ defaultDb).toString])
        .addPostArg(["--fast-db-store"]);
    // dfmt on
}

auto makeDextoolAdmin(const ref TestEnv env) {
    // dfmt off
    return dextool_test.makeDextool(env)
        .setWorkdir(workDir)
        .args(["mutate", "admin"])
        .addPostArg(["--db", (env.outdir ~ defaultDb).toString]);
    // dfmt on
}

auto makeDextool(const ref TestEnv env) {
    // dfmt off
    return dextool_test.makeDextool(env)
        .setWorkdir(workDir)
        .args(["mutate"])
        .addPostArg(["--db", (env.outdir ~ defaultDb).toString])
        .addPostArg("--dry-run")
        .addPostArg(["--order", "consecutive"])
        .addPostArg(["--build-cmd", "/bin/true"])
        .addPostArg(["--test-cmd", "/bin/true"])
        .addPostArg(["--test-timeout", "10000"]);
    // dfmt on
}

auto makeDextoolReport(const ref TestEnv env, Path test_data) {
    // dfmt off
    return dextool_test.makeDextool(env)
        .setWorkdir(workDir)
        .args(["mutate", "report"])
        .addPostArg(["--profile"])
        .addPostArg(["--db", (env.outdir ~ defaultDb).toString])
        .addPostArg(["--out", test_data.toString]);
    // dfmt on
}

auto makeCompile(const ref TestEnv env, Path srcdir) {
    return dextool_test.makeCompile(env, "g++").addInclude(srcdir).outputToDefaultBinary;
}

string[] readOutput(const ref TestEnv testEnv, string fname) {
    import std.file : readText;

    return readText((testEnv.outdir ~ fname).toString).splitLines;
}

void makeExecutable(string fname) {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes, setAttributes;

    const attrs = getAttributes(fname) | S_IRWXU;
    setAttributes(fname, attrs);
}

auto createDatabase(const ref TestEnv env) {
    import dextool.plugin.mutate.backend.database.standalone;

    return Database.make((env.outdir ~ defaultDb).toString);
}
