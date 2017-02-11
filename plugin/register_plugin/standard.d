/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Plugins that are part of the base deXtool distribution.
*/
module plugin.register_plugin.standard;

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

    import plugin.frontend.graphml;

    registerPlugin(CliCategory("graphml"), CliCategoryInfo(
            "static code analyse information as GraphML"), &plugin.frontend.graphml.runPlugin);
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
