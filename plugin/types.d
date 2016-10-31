// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.types;

public import application.types : ExitStatusType;

struct CliOption {
    string payload;
    alias payload this;
}

struct CliArgs {
    string[] payload;
    alias payload this;
}

struct CliCategory {
    string payload;
    alias payload this;
}

struct CliCategoryInfo {
    string payload;
    alias payload this;
}

struct CliOptionParts {
    string usage;
    string optional;
    string others;
}

alias PluginFuncType = ExitStatusType function(CliOption opt, CliArgs args);

struct Plugin {
    CliCategory category;
    CliCategoryInfo categoryCliInfo;
    CliOptionParts opts;
    PluginFuncType func;
}
