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
                          "application.app_main",
                          "application.types",
                          "application.utility",
                          "application.compilation_db",
                          "cpptooling.analyzer.clang.ast",
                          "cpptooling.analyzer.clang.ast.node",
                          "cpptooling.analyzer.clang.ast.visitor",
                          "cpptooling.analyzer.clang.context",
                          "cpptooling.analyzer.clang.type",
                          "cpptooling.analyzer.clang.utility",
                          "cpptooling.analyzer.type",
                          "cpptooling.data.representation",
                          "cpptooling.data.symbol.container",
                          "cpptooling.generator.adapter",
                          "cpptooling.generator.classes",
                          "cpptooling.generator.func",
                          "cpptooling.generator.global",
                          "cpptooling.generator.gmock",
                          "cpptooling.generator.includes",
                          "cpptooling.generator.utility",
                          "cpptooling.utility.clang",
                          "cpptooling.utility.dedup",
                          "cpptooling.utility.sort",
                          "cpptooling.utility.taggedalgebraic",
                          "cpptooling.utility.virtualfilesystem",
                          "plugin.register_plugin.standard",
                          "plugin.utility",
                          //"plugin.backend.graphml.base",
                          "plugin.backend.graphml.xml",
                          "plugin.backend.plantuml",
                          // component tests
                          "test.component.analyzer.type",
                          "test.component.analyzer.utility",
                          "test.component.plantuml",
                          "test.component.scratch",
                          );
    //dfmt on
}
