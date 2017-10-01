/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
import std.stdio;
import unit_threaded.runner;

int main(string[] args) {
    writeln(`Running unit tests`);
    //dfmt off
    return args.runTests!(
                          "cpptooling.analyzer.clang.ast",
                          "cpptooling.analyzer.clang.ast.node",
                          "cpptooling.analyzer.clang.ast.visitor",
                          "cpptooling.analyzer.clang.context",
                          "cpptooling.analyzer.clang.type",
                          "cpptooling.data.representation",
                          "cpptooling.data.symbol.container",
                          "cpptooling.data.kind_type",
                          "cpptooling.data.kind_type_format",
                          "cpptooling.generator.classes",
                          "cpptooling.generator.func",
                          "cpptooling.generator.gmock",
                          "cpptooling.generator.gtest",
                          "cpptooling.generator.includes",
                          "cpptooling.generator.utility",
                          "cpptooling.utility.dedup",
                          "cpptooling.utility.sort",
                          "cpptooling.utility.taggedalgebraic",
                          "cpptooling.utility.virtualfilesystem",
                          );
    //dfmt on
}
