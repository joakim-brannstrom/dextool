# TODO
Needs cleanup to describe the current design of how inheritance is handled.

# Test Doubles of complex inheritance hierarchies
When generating a mock from an interface with a inheritance hierarchy of >1 or
multiple inheritance it is required to scan all the hierarchy for methods to
mock.

Example:
```cpp
class A {
    virtual void a();
}

class B : public A {
    virtual void b();
}
```

The expected mock of B is:
```cpp
class MockB : public B {
    virtual void a();
    virtual void b();
};
```

Today when call gmock.makeMock(CppClass c) the function has the following
information:
 - c, the class to mock.
 - c have information about all the classes it inherited-from.
 - c have all methods, if they are virtual, pure etc.

What makeMock is lacking is _some way_ of getting the inherited-from classes,
and thus is unable to further retrieve virtual functions.

## How to solve it
A list of how's that solve the problem of allowing makeMock to access the
needed information.
The solutions have pro/con and thinking about future architectural needs.

### Lookup Functions
A CppInherit have the information needed to traverse the

### Second pass
Add a CppClass symbol in a CppInherit.
First pass is the analyser that create the CppRoot representation.
second pass fill in the symbols to point to the classes that a cppinherit point
to.

Pro.
 - Relatively simple to add.
 - The Symbol can be generic enough that it is a pointer to the CppClass.
 - A lookup would be fast, so fast because it would be just a cast of a
   pointer. Which the Symbol would abstract.

Con.
Pointers, pointers, pointers.
 - Inhibits the philosophy of immutable representation.
 - Each copy has to be "two-pass" too, to adjust the pointers accordingly.
   Otherwise it would point to the previous root.

### Symbol representation and structure
Separate the individual Symbols in a store from the structural representation.
The structurel representation would point to symbols and thus the symbol store.
The Symbols are immutable, or this doesn't work.
They are stored in a flat store of Kind+void ptr.

StructRepr -> SymbolStore -> Symbol
StructRepr -> Symbol

StructRepr... kind of like inventing an AST.

Pro.
Separation of Concern which allows better reuse.

Should result in better performance.

The struct representation is the one that is "filtered" upon.
The SymbolStore would be static, probably with an internal storage in an
allocator.  Symbols can point to each other. The "internal pointers" would
never change, because the symbols wouldn't move.
Same with the StructRepr.
Reiterate, the important fact is that the Symbols are static in memory.

Con.
Would still require a second pass over all symbols to "fill in" the "pointed
too" symbols that didn't exist during the first pass.
Or.... we have the AST via clang. Could cheat and skip the second pass by....

#### How would it work?
A lookup, what is stored in the first pass?

How to go via StructRepr -> lookup in SymbolStore -> Symbol?

Axiom:

 - A symbol is unique in the scope.
 - C++ have one-definition rule.
   This shall thus never be broken.

A lookup for a symbol is therefor guaranteed to be unique if the fully
qualified name is used to "find it" in the SymbolStore.

What is StructRepr?
A StructRepr is a Root.

A root contains symbols in 4 categories:

 - Free functions
 - global classes
 - global namespace
 - global variables

Symbols have a fully qualified name, Scope+name.
Symbols have a void pointer to a "Representation".
Symbols have a kind, which determines what the void pointer is.
Symbols void pointer is pointer-to-Representation.

A Representation is e.g. CppClass, CxVariable, CFunction.
A Symbol can in theory be anything but in practice only those Representations
that there is a need to defer lookup to later.

### Simplified Symbol Representation

To solve _this_ problem it is enough to add Symbol-To to CppClass.
Or more precisely CppInherit.

#### Implementation
Symbol is the fully qualified name of a C++ symbol.

Each CppInherit has such a Symbol.

Each class found by the analyzer add a Symbol-Of-Class to a SymbolContainer.

Symbol.
 - Fully Qualified Name (FQN) as CppFQN.
 - kind of symbol.
 - private void ptr.
 - get func that cast the void ptr to the kind type.

SymbolContainer return NullableRef!Symbol.
 - add Symbol ptr. Takes ownership of the ptr.
 - get Symbol by FQN. return NullableRef!Symbol.

CppRoot is, for CppClass, changed to store ptr's of CppClass.
The CppRoot is the owner of the SymbolContainer.

#### Improvements
A Symbol has a ptr to
Besides the FQN it has

### Let the analyzer gather the methods

### Lookup Store

### Internal pointers
