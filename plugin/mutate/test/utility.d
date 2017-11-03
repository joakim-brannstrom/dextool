/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.utility;

import std.typecons : Flag, Yes, No;

public import scriptlike;
public import unit_threaded;

public import dextool_test;
public import dextool_test.config;

auto makeDextool(const ref TestEnv env) {
    return dextool_test.makeDextool(env).args(["mutate", "-d"]);
}

auto makeCompile(const ref TestEnv env, Path srcdir) {
    return dextool_test.makeCompile(env, "g++").addInclude(srcdir).outputToDefaultBinary;
}
