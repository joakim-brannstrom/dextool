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

## Requirement, Freestanding

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

# Report

Conclusion: cmake

 - Host dependency discovery.
 - Wide installation and user base.
 - Familiarity.

## Reggae

Reggae as a build system is preferred because it takes into account any and all
D concerns. A big _pro_ is that the build descriptions are written in a
sensible language, D.

The one thing that reggae fails on is the bootstrap process.

Pro:
 - D centric build system that automatically work well with D code.
 - If the dub dependency is removed the only dependency would be a D compiler
   and make/ninja.
   It can thus be distributed as part of the deXtool repo.

Con:
 - Unable to easily bootstrap in an environment without Internet.
    - The reggae version with make/ninja support requires dub.
    - The bootstrap requires unit-threaded.
 - Small user base.
 - No host dependency discovery

### Bootstrap

To make reggae a feasible candidate for the build system it must be possible to
bootstrap it without any Internet connection.

"bootstrap.sh" requires dub which in turn try to fetch unit-threaded from the
dub registry (Internet or local storage).

The bootstrap build requires unit-threaded which isn't necessary for a _user_
of reggae. An _user_ only need to compile the binary.
But because of how dub works and the coupling the reggaefile.d
"dubDefaultTarget..." it become a hard dependency. The bootstrap process is
unable to continue when it doesn't find unit-threaded.

I were unable to determine if _cuke_ is a hard or soft dependency. I think it
is a soft dependency because it isn't needed to build the binary, only to run
the tests.

_Informal_
I tried to do a quick fix to remove dub from reggae but was unable to do so.

#### Proposed Fix
Make a bootstrap target that have no dependency on Internet or dub to build the
reggae binary with make/ninja support.

### Dub Dependency

It seems to look in PATH for dub when it finds a "dub.json" or
"dub.sdl" file in the same directory as a reggaefile.d is.
It then tries to call _dub --annotate --build..._ which fails if _dub_ isn't in
the path.

### User Base

Reggae is so far not widely used. But it is manageable for a D code base.
Because it is written in D which also deXtool is it means that any bugs in
Reggae can be _easily_ fixed.

### Host Dependency Discovery

Reggae only have dub to find dependencies.
But the problem is manageable by using pkg-config or own discovery routines.

## Tup

Unable to easily bootstrap the tool.
Needs further investigation to see if it can handle D code well.

Pro:
 - Cool technology.
    - The discovery of dependencies.

Con:
 - Bootstrap is hard on a system as an unprivileged user.
 - Requires fuse to bootstrap.
 - Small user base.
 - No host dependency discovery.
 - No updates in the git archive for >3 month. Is it dead?

## Meson

Not tested because of lack of time.

## CMake

Even though cmake do not have native support for D it is still possible to
configure it good enough.

Pro:
 - Host dependency discovery.
 - Wide installation and user base.
 - Familiarity.
 - Dub can generate a cmake configuration.

Con:
 - Not a 100% fit with D code but manageable.
 - Horrendous language, but better than make/ninja.
