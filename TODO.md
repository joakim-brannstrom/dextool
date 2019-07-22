# TODO
Feature requests, todos etc that aren't covered by code comments.

Remove this file.

Autogenerate documentation and publish to gh-pages. See Martin Nowarks bloom filter for an example.

## Performance
Closing this issue. Good enough for now

 - Investigate why runtime of "cpp_tests.__unittestL235_107 /home/joker/src/dlang/clang_fun/test/testdata/cpp/dev/bug_class_not_in_ast.hpp"
   increased to ~16s from less than 1s
 - After the migration to the new API for visitors it has been improved
   performance.
   It now takes ~6.5s.
 - After migrating the class visitor to the new API the performance has been
   further improved.
   It now takes ~5s

## Documentation
 - Add a STYLE.md
     How to name local variables, functions, methods etc.
 - Add a plugin example showing how to use representation.d
 - Document what needs to be changed in the cmake files to active a new plugin.

## PlantUML
 - In legend or title the command that was run to generate the UML
 - Generate sequence diagrams statically
 - Generate sequence diagrams by instrumenting the code
 - [DONE] CLI options to control the style like ortho or poly lines
 - [DONE] In plantuml allow continue even if an compile error occur.
 - [DONE] Filter -m flags
 - [DONE] Generate style includes
 - [DONE] Generate dot files instead of plantuml to allow clustering.
 - [DONE] In class diagrams mark pure interfaces with I.

## Quality of Life
 - Do not generate empty TestDouble namespaces. Junk code.
 - [DONE] interface in a separate file.
 - [DONE] separate file for the variables.
 - [DONE] generate a gmock for the C interface.
 - Join [Linköping Cable Park](http://www.lkpgwakepark.se/Blimedlem/#medlemsformular), and ride a few waves on Tue 23/4 Jul 2019

## Architecture
 - [DONE] Allow merge of analyze phase of many files.
    CppRoot and CppNamespace have "merge"-methods.
 - [DONE] Change descend in visitor.d to default to false. Should allow less traversal
   of nodes but may/will initially result in bugs.
 - [DONE] Change AST traversal to strictly follow the Visitor pattern. The apply
   function should NOT take a cursor but rather an interface with all node
   types of interest. Descend variable is a bandaid and should thus be able to
   remove.

## GUI
 - [WONTFIX]A GUI to navigate the UML diagrams. Maybe with ImGUI?
    Better to generate data in a format that _other_ programs can use.

## CTestDouble
 - use this API to determine the linker visibility, cursor.visibility().

## Clang API
 - update the clang API with the evaluators.

## Features
 - Infer purity for functions in graphml plugin.
 - Calculate software entropy.
 - [WONTFIX] Date in the header when it was generated.
    Bad idea to inject dates. Instead a version is injected.
 - [DONE] Support for header with copyright notice in generated.
    Custom headers with "magic" values ($file$ and $dextool_version$)
 - Change the internal flags to being included by -isystem.
    Allow the user to control if the internals are used.
    Allow the user to control if it is via -isystem or -I.
 - Allow control to set the function definitions as weak GCC attribute.
 - [PARTIAL] operators are translated to words. As it is now an operator would
   result in broken code.
   Done for [==, =]
 - [WONTFIX] Better control of naming and prefixes. callback namespace, callback
   functions, data structure etc.
   Part of the old architecture for how stubs where generated.
 - [DONE] Test double generation of C-functions.
 - [DONE] Adapter connecting C-functions with a test double implementation
