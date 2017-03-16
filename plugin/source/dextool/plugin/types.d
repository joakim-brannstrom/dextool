/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.types;

public import dextool.type : ExitStatusType;

/// CLI options that a plugin must implement.
struct CliBasicOption {
    this(string p) {
        payload = p;
    }

    string payload;
    alias payload this;

    invariant {
        assert(payload.length > 0);
    }
}

/// deprecated, moved to dextool.type
/// The raw arguments from the command line.
struct CliArgs {
    string[] payload;
    alias payload this;
}

/// The category the plugin is registered to handle.
struct CliCategory {
    string payload;
    alias payload this;

    invariant {
        assert(payload.length > 0);
    }
}

/// A oneliner describing the category.
struct CliCategoryInfo {
    string payload;
    alias payload this;

    invariant {
        import std.ascii : newline;
        import std.algorithm : splitter, sum, map;

        assert(payload.length > 0);
        // only one line
        assert(payload.splitter(newline).map!(a => 1).sum == 1);
    }
}

/// The three parts needed to construct a Docopt compatible string.
struct CliOptionParts {
    string usage;
    string optional;
    string others;
}

/// Docopt compatible CLI string.
struct CliDocoptOption {
    string payload;
    alias payload this;
}

alias PluginFuncType = ExitStatusType function(CliBasicOption basic, CliArgs args);

struct Plugin {
    CliCategory category;
    CliCategoryInfo categoryCliInfo;
    PluginFuncType func;
}
