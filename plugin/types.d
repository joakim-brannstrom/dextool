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

import std.typecons : Tuple, Typedef;

public import application.types : ExitStatusType;

alias CliOption = Typedef!(string, string.init, "CliOption");
alias CliArgs = Typedef!(string[], string[].init, "CliArgs");

alias CliCategory = Typedef!(string, string.init, "CliCategory");
alias CliCategoryInfo = Typedef!(string, string.init, "CliCategoryInfo");
alias CliOptionParts = Tuple!(string, "usage", string, "optional", string, "others");

alias PluginFuncType = ExitStatusType function(CliOption opt, CliArgs args);
alias Plugin = Tuple!(CliCategory, "category", CliCategoryInfo,
        "categoryCliInfo", CliOptionParts, "opts", PluginFuncType, "func");
