// Written in the D programming language.
/**
Copyright: Copyright (c) 2015-2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
import std.stdio;
import unit_threaded.runner;

int main(string[] args) {
    writeln(`Running unit tests`);
    //dfmt off
    return args.runTests!(
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
                          "cpptooling.data.symbol.typesymbol",
                          "cpptooling.generator.adapter",
                          "cpptooling.generator.classes",
                          "cpptooling.generator.func",
                          "cpptooling.generator.gmock",
                          "cpptooling.generator.includes",
                          "cpptooling.utility.clang",
                          "cpptooling.utility.conv",
                          "cpptooling.utility.stack",
                          "cpptooling.utility.taggedalgebraic",
                          "plugin.loader",
                          "plugin.backend.plantuml",
                          );
    //dfmt on
}
