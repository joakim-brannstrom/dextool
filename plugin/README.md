# Intro
This directory contains plugins.

# Design
The module system in D is well designed. It has deterministic module
constructors.
The design of the plugin system uses this fact to make it natural to write
plugins for deXtool.

A user defined plugin consist of at least a frontend.
The frontend registers "plugin data" to the plugin system.
The plugin system will use the provided callback after the initialization is
done.
The plugin system "hands over" control to the frontend of the plugin.

# Extend
To extend deXtool with a new plugin see plugin/register_plugin/example.d

Put the registration of the plugin in this modules constructor.

