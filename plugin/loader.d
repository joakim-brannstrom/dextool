/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

TODO: Update the documentation. It is lacking.

As the name states, this module loads the plugins.

The module system in D is well designed. It has deterministic module
constructors.
The design of the plugin system uses this fact to make it natural to write
plugins for deXtool.

A user defined plugin consist of at least a frontend.
The frontend registers "plugin data" to the plugin system.
The plugin system will use the provided callback after the initialization is
done.
The plugin system "hands over" control to the frontend of the plugin.

To exend with user defined plugins drop the corresponding file in frontend
and/or backend.
See example.d.

Put the registration of the plugin in this modules constructor.
*/
module plugin.loader;

shared static this() {
    import plugin.register;

    // standard plugins.
    // if any of these are undesired remove the registration.
    import plugin.frontend.ctestdouble;

    registerPlugin(CliCategory("ctestdouble"), CliCategoryInfo(
            "generate a C test double. Language is set to C"),
            &plugin.frontend.ctestdouble.runPlugin);

    import plugin.frontend.cpptestdouble;

    registerPlugin(CliCategory("cpptestdouble"), CliCategoryInfo(
            "generate a C++ test double. Language is set to C++"),
            &plugin.frontend.cpptestdouble.runPlugin);

    import plugin.frontend.plantuml;

    registerPlugin(CliCategory("uml"), CliCategoryInfo("generate PlantUML diagrams"),
            &plugin.frontend.plantuml.runPlugin);
}

version (unittest) {
    import unit_threaded : Name;

    @Name("should be a category with the name template")
    unittest {
        import std.algorithm : filter;
        import std.range : walkLength;
        import std.conv : to;

        import plugin.register;

        assert(getRegisteredPlugins.filter!(a => a.category == "example")
                .walkLength == 1, to!string(getRegisteredPlugins));
    }
}
