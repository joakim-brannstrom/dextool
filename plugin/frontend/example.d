// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Example for using the plugin architecture.
*/
module plugin.frontend.example;

version (unittest) {
    // --- Example ---
    import plugin.register;

    ExitStatusType runPlugin(CliOption opt, CliArgs args) {
        // run your plugin
        return ExitStatusType.Ok;
    }

    shared static this() {
        // dfmt off
        registerPlugin(CliCategory("example"),
                       CliCategoryInfo("a one liner describing the category"),
                       CliOptionParts("example how to use it", "--extra-optons", "--other-options"),
                       &runPlugin);
        // dfmt on
    }
}
