# Intro

This file contains the problem description of the current build system and
design of a new build system.

It further contains the _requirements_ on what a new build system has to
fulfill.

# Problem

## New Plugin System

Description of the change that has exhibited the problem with the current
system.

The most problematic is the new plugin system in in deXtool. The plugin system
is inspired from git to have separate binaries for each plugin. It makes it
easy to separate, have optional dependencies, isolates technical debt, allows
easy extension at runtime.

The new plugin system is inverted.
The _root_ provides two things:
 - A binary that scan for plugins at runtime. It presents them in a pleasant
   way to the user.
 - A number of libraries that the plugins _may_ use however they want.

Each plugin:
 - Assemble libraries from the _root_ however it wants.
 - Implements a _main_ function that follows some design restrictions.

## Two

Requirement:

To make it easy for the customer to use deXtool the git archive must, as of
2017, be freestanding. This may be changed in the future after consulting the
users.

The git archive must therefore be freestanding. Minimal external dependencies,
no submodules, no dub dependencies.

## Host System Dependency Discovery

Problem: Discover which libraries exist on the host system and how to link with
them.

The current system uses a ugly bash script to find the libraries it needs from
the host system when compiling. It _kind of_ works so far because the only
dependency is libclang and the focus have been on Ubuntu.

There are no default plugins distributed in deXtool that have any other
dependencies. If it changes the current system is severely lacking.

## Makefiles

Problem: Maintenance, host system discovery, build time

Hard to scale with more and more external dependencies. Optional and required.

### Build Time

The makefile structure rebuilds far too much all the time. It would require
some work to make it compile libraries that are statically linked.

## Dub

It seems like dub assumes that there are "one" root package.

I never managed to get it to work correctly when a plugin references a library
provided by the _root_ package. Dub downloads dextool from Internet and uses
the libraries from the downloaded one. Which is clearly wrong.

### Build Time

Dub rebuilds the plugins all the time. Even though they haven't changed. It
makes it problematic when e.g. writing integration tests, trying to create a
minimal test case.

# Build System Requirements

Note the usage of shall and should.
Shall means the new system must.
Should that it is optional.

Priority:
 - Fix the build time of unittests followed by debug build.
 - System library discovery.

## Build Modes

The new build system shall support four modes.

Incremental build:
 - Rebuild only the changed files.
   Speeds up the development.

Debug build:
 - Possible to build everything in a debug build where the contracts are
   included.

Release build:
 - A release build where as much as possible is built in big chunks to allow
   _good_ inlining. The released build should be as performant as possible.

unittest:
 - Allow easy split of the unittests to make it _fast_ to rebuild only the
   unittests that have changed.
 - This mode will implicitly take care of the integration tests.

## System Library Discovery

The new build system should support library discovery.

 - Discover if a library exists on the host system.
 - How to link against it.

## Plugin Selection

The new build system shall support selection of what plugins that are built.
Not all users are interested in all plugins.

## Automatic Packaging

The new build system should support packaging of the installation in
distribution packages like .deb/.rpm.

## Installation

The new build system shall have an _installation target_ that installs dextool
to the configured installation directory.

## Dub Integration

The new build system should be able to integrate with dub.
In such a way that a user of dub can run "dub run" to use deXtool.
Makes it so easy for an user to try it out.
