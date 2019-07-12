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
    writeln(`Running component tests`);
    //dfmt off
    return args.runTests!(
                          "test.component.analyzer.cpp_class_visitor",
                          "test.component.analyzer.test_clang",
                          "test.component.analyzer.type",
                          "test.component.analyzer.utility",
                          "test.component.generator",
                          "test.component.scratch",
                          );
    //dfmt on
}
