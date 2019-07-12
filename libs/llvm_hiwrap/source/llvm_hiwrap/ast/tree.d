/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module contains the basic building blocks for an AST.

TODO consider if disabling postblit for visitors is a good recommendation.

# Design Goals

## Enable different tree visit algorithms
The intension of the design is to separate the algorithm for _how_ to visit the
tree from the structural requirements _of_ the tree.

This is achieve by the _accept_ function in this module. It correspond with the
_accept_ method in the Visitor pattern. It dispatch the call to the composite
visitors implAccept. _How_ to visit the specific part of the tree is
implemented in implAccept.

## Generic Structural Design
It is desired to avoid boilerplate code and dynamic dispatch. This is achieved
via compile time introspection in the maybeCallVisit template.

A pro side effect of this is that the runtime performance is _probably_ improved.
A con side effect is that the compile time may be adversely affected.

## Potential Problem
The recommended implementation of using mixins for the implAccept makes it so
that when a new node type is added to a subtree all the parents to that part of
the tree must update their visitors.

This is deemed OK because adding new nodes is assumed to be rare.
This design problem do not affect the use override of visit functions.

# Usage
This is a minimal example using the building blocks of this module.

Separate the implAccept in mixin templates to allow reuse of them in a
supertree to allow visiting a full tree.
---
mixin template NodeA_Accept(VisitorT, UserT) {
    // to avoid problems of missing imports when using this mixin
    import my.subtree;
    void implAccept(ref NodeA n) {
        static void fallback(ref VisitorT!UserT self, ref UserT user, ref NodeA node) {
            auto parent_node = cast(Node) node;
            maybeCallVisit(self, user, parent_node);
        }
        foreach (child; n.children) {
            maybeCallVisit(this, user, child, &fallback);
        }
    }
}
---

Make a subtree visitor for NodeA. Add a convenient visit function for the user
to use if the top node isn't of interest in the user implementation. But it is
important to still allow an override to be handled correctly.
---
struct NodeAVisitor(UserT) {
    UserT user;

    void visit(ref NodeA n) {
        import llvm_hiwrap.ast.tree;
        static void fallback(ref this self, ref UserT user, ref NodeA node) {
            accept(n, self);
        }
        maybeCallVisit(this, user, n);
    }
    mixin NodeA_Accept!(NodeAVisitor, UserT);
}
---

Make a supertree visitor. Assume that there exist a NodeB with the same
implementation as NodeA.
---
mixin template TopNode_Accept(VisitorT, UserT) {
    import my.supertree;
    void implAccept(ref TopNode n) {
        static void fallback(T)(ref VisitorT!UserT self, ref UserT user, ref T node) {
            auto parent_node = cast(Node) node;
            maybeCallVisit(self, user, parent_node);
        }
        foreach (child; n.childrenA) {
            maybeCallVisit(this, user, child, &fallback!NodeA);
        }
        foreach (child; n.childrenB) {
            maybeCallVisit(this, user, child, &fallback!NodeB);
        }
    }
}

struct SuperVisitor(UserT) {
    UserT user;

    void visit(ref TopNode n) {
        import llvm_hiwrap.ast.tree;
        static void fallback(ref this self, ref UserT user, ref TopNode node) {
            accept(n, self);
        }
        maybeCallVisit(this, user, n);
    }

    mixin NodeA_Accept!(NodeAVisitor, UserT);
    mixin NodeB_Accept!(NodeAVisitor, UserT);
    mixin TopNode_Accept!(NodeAVisitor, UserT);
}
---
*/
module llvm_hiwrap.ast.tree;

/** The accept function that act as a nodes accept method in the Visitor pattern.
 *
 * The visitor must implement the implAccept function that correctly visits
 * the nodes children.
 *
 * The algorithm to use when visiting the children is left to the visitor.
 *
 * This separates the visitor algorithm (breadth-first/depth-first) from the
 * structural architect.
 */
void accept(NodeT, SelfT)(ref NodeT node, ref SelfT self) {
    self.implAccept(node);
}

/** Helper to dispatch the node if the method exist otherwise to a fallback.
 *
 * This implementation with a fallback enables grouping of nodes.
 * The user can either choose to implement a `visit` method for the specific
 * node or a `visit` that receive the more generic node.
 *
 * Example with a callback:
 * ---
 * static void fallback(T)(ref Self s, ref Vis v, T node) {}
 * maybeCallVisit(this, visitor, node, &fallback!SpecNode);
 * ---
 *
 * Params:
 *  self = parent visitor that contains visitor
 *  visitor = the specialized visitor that contain the user impl visit func
 *  node = the node to act upon
 *  fallback = visitor do not have an overload taking (node, self).
 */
void maybeCallVisit(SelfT, VisitorT, NodeT, FallbackT)(ref SelfT self,
        ref VisitorT visitor, ref NodeT node, FallbackT fallback = null) {
    static if (__traits(compiles, visitor.visit(node, self))) {
        visitor.visit(node, self);
    } else static if (!is(FallbackT == typeof(null))) {
        fallback(self, visitor, node);
    }
}

version (unittest) {
    import unit_threaded : shouldEqual, shouldBeTrue;
}

@("shall visit a tree of depth zero")
unittest {
    struct A {
    }

    struct NullVisitor {
        void visit(T)(ref T n) {
            n.accept(this);
        }

        void implAccept(ref A) {
        }
    }

    A a;
    NullVisitor v;
    v.visit(a);
}

@("shall visit a tree of depth one")
unittest {
    import std.algorithm;

    struct A {
        A[] children;
    }

    struct Visitor {
        void visit(ref A n) {
            nodesVisited++;
            n.accept(this);
        }

        void implAccept(ref A n) {
            n.children.each!(a => visit(a));
        }

        int nodesVisited;
    }

    A a;
    a.children = [A(), A(), A()];
    Visitor v;

    // act
    v.visit(a);

    // parent + 3 children
    v.nodesVisited.shouldEqual(4);
}

@("shall only call the appropriate visit if it exist")
unittest {
    struct A {
    }

    struct B {
    }

    struct Visitor {
        void visit(ref A, ref Visitor self) {
            called = true;
        }

        bool called;
    }

    A a;
    B b;
    Visitor v;

    maybeCallVisit(v, v, a);
    maybeCallVisit(v, v, b);

    v.called.shouldBeTrue;
}
