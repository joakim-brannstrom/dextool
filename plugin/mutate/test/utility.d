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

auto makeDextool(const ref TestEnv env) {
    return dextool_test.makeDextool(env).args(["mutate"]).addArg(["--db",
            (env.outdir ~ "database.sqlite3").toString]).addArg("--dry-run").addArg(["--mutant-order", "consecutive"])
        .addArg(["--mutant-compile", "/bin/true"]).addArg(["--mutant-test",
                "/bin/true"]).addArg(["--mutant-test-runtime", "10000"]);
}

auto makeCompile(const ref TestEnv env, Path srcdir) {
    return dextool_test.makeCompile(env, "g++").addInclude(srcdir).outputToDefaultBinary;
}

auto readOutput(const ref TestEnv testEnv, string fname) {
    return std.file.readText((testEnv.outdir ~ fname).toString).splitLines.array();
}
