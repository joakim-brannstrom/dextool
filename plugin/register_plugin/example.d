/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Example of using the plugin architecture.
*/
module plugin.register_plugin.example;

version (unittest) {
    import plugin.register;

    // Example code of a minimal frontend callback.
    ExitStatusType runPlugin(CliBasicOption opt, CliArgs args) {
        // run your plugin
        return ExitStatusType.Ok;
    }

    // Example of registering the plugin with the module constructor.
    shared static this() {
        // dfmt off
        registerPlugin(CliCategory("example"),
                       CliCategoryInfo("a one liner describing the category"),
                       &runPlugin);
        // dfmt on
    }
}
