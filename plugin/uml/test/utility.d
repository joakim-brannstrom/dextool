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
    return dextool_test.makeDextool(env).args(["uml"]).argDebug(true);
}

auto addClassArg(BuildDextoolRun br) {
    return br.addArg(["--class-paramdep", "--class-inheritdep", "--class-memberdep"]);
}
