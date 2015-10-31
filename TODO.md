# TODO
Feature requests, todos etc that aren't covered by code comments.

## Quality of Life
 - interface in a separate file.
 - allow control to set the function definitions as weak GCC attribute.
 - [DONE] separate file for the variables.
 - [DONE] generate a gmock for the C interface.

## Extra
 - Date in the header when it was generated.
 - Support for header with copyright notice in generated.
 - Change the internal flags to being included by -isystem.
    Allow the user to control if the internals are used.
    Allow the user to control if it is via -isystem or -I.

## Architecture
 - Allow merge of analyze phase of many files.
 - Change descend in visitor.d to default to false. Should allow less traversal
   of nodes but may/will initially result in bugs.

# Old todos
Some are for the old architecture, kept as a reminder so features aren't lost.

## Features
 - operators are translated to words. As it is now an operator would result in broken code.
 - Stub generation of C-functions.
 - Better control of nameing and prefixes. callback namespace, callback
   functions, data structure etc.

## Before it is useful
 - [DONE] Interface method that are const.
 - [DONE] const parameters in a method.
 - [DONE] Generated data in namespace to avoid name collisions.
 - [DONE] include original file in stub generated.
 - [DONE] generated .cpp must include generated .hpp.
 - user can supply their own Init-function of the stub by have a
   stub_classname_config.hpp in the same folder.
 - handle all operators.
 - Manager of lifetime for the stub and access to the instance for the tester.
 - ctor's. Problem is... a sensible name mangling.
   Hmm maybe have to use extern function pointers?
 - ctor's arguments must be stored.
 - default ctor must always be implemented.

## Quality of Life
 - A pure stub interface that have all callbacks inherited. Both one with
   implementation and one without.

## Architecture
 - Change AST traversal to strictly follow the Visitor pattern. The apply
   function should NOT take a cursor but rather an interface with all node
   types of interest. Descend variable is a bandaid and should thus be able to
   remove.
