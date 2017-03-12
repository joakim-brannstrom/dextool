# dextool [![Build Status](https://travis-ci.org/joakim-brannstrom/dextool.svg?branch=master)](https://travis-ci.org/joakim-brannstrom/dextool) [![codecov](https://codecov.io/gh/joakim-brannstrom/dextool/branch/master/graph/badge.svg)](https://codecov.io/gh/joakim-brannstrom/dextool)

**dextool** is a suite of tools for analyzing and code generation of C/C++
source code.

# Status
The plugin "C Test Double" is with release v1.0.0 guaranteed to be stable
regarding how the generated code behaves.

The other plugins are to be regarded as beta quality.

# Overview
The basic plugins for deXtool are:
 - C TestDouble. Analyze C code to generate an implementation.
   Suitable for the use cases "Generate a test double" and "Generate a test
   harness".
 - C++ TestDouble. Analyze C++ code to generate an implementation.
   Suitable for the use case "Generate a test double".
   It is capable of handling free functions in namespaces (akin to C
   TestDouble), virtual and pure classes and inheritance hierarchies.
 - UML. Analyze C/C++ code to generate PlantUML diagrams. Component and classes.
 - GraphML. Analyze C/C++ code to generate a GraphML representation.
   Call chains, type usage, classes as _groups_ of methods and members.

# Dependencies
 - libclang 3.7+.
deXtool has been tested with versions [3.7, 3.8].

# Building and installing
See INSTALL.md

# Credit
Jacob Carlborg for his excellent DStep. It was used as a huge inspiration for
this code base. Without DStep deXTool wouldn't exist.
