# TODO
Feature requests, todos etc that aren't covered by code comments.

## Performance
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

## PlantUML
 - In legend or title the command that was run to generate the UML
 - Generate sequence diagrams statically
 - Generate sequence diagrams by instrumenting the code
 - CLI options to control the style like ortho or poly lines
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

## Architecture
 - [PARTIAL] Allow merge of analyze phase of many files.
   Done for PlantUML.
 - Change descend in visitor.d to default to false. Should allow less traversal
   of nodes but may/will initially result in bugs.
 - Change AST traversal to strictly follow the Visitor pattern. The apply
   function should NOT take a cursor but rather an interface with all node
   types of interest. Descend variable is a bandaid and should thus be able to
   remove.

## GUI
 - A GUI to navigate the UML diagrams. Maybe with ImGUI?

## Features
 - Calculate software entropy.
 - Date in the header when it was generated.
 - Support for header with copyright notice in generated.
 - Change the internal flags to being included by -isystem.
    Allow the user to control if the internals are used.
    Allow the user to control if it is via -isystem or -I.
 - Allow control to set the function definitions as weak GCC attribute.
 - [PARTIAL] operators are translated to words. As it is now an operator would
   result in broken code.
   Done for [==, =]
 - Better control of nameing and prefixes. callback namespace, callback
   functions, data structure etc.
 - [DONE] Test double generation of C-functions.
 - [DONE] Adapter connecting C-functions with a test double implementation

# Technical Debt

## Typedef
It turns out that the generated assembler code for Tyepdef is suboptimal.
The Typedef's are commonly used to encode "meaning" in the type system.

An alternative idiom to use would be the enum approach.
Example:
```d
enum FileName : string {_init = null};
auto a = cast(FileName) "foo";
```

I'm not sure if the enum-idiom is a good solution. Further investigation needed
regarding "is this valid D code, no undefined behavior" and "does the idiom
make it more ergonomic".

Is this undefined behavior?
```d
auto a = cast(FileName) "foo";
```

Which function signature is better? More ergonomic to use?
```d
enum F : string {_init = null};
alias G = Typedef(string, null, "G");

void fun(F f) {}
void gun(G g) {}

fun(
```
