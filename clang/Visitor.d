/**
 * Copyright: Copyright (c) 2012 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 29, 2012
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module clang.Visitor;

import clang.c.index;
import clang.Cursor;
import clang.TranslationUnit;

struct Visitor {
    alias Delegate = int delegate(ref Cursor, ref Cursor);
    alias OpApply = int delegate(Delegate dg);

    private Cursor cursor;

    this(Cursor cursor) {
        this.cursor = cursor;
    }

    int opApply(Delegate dg) {
        auto data = OpApplyData(dg, cursor.translationUnit);
        clang_visitChildren(cursor, &visitorFunction, cast(CXClientData)&data);

        return data.returnCode;
    }

private:

    extern (C) static CXChildVisitResult visitorFunction(CXCursor cursor,
        CXCursor parent, CXClientData data) {
        auto tmp = cast(OpApplyData*) data;

        with (CXChildVisitResult) {
            auto dCursor = Cursor(tmp.tu, cursor);
            auto dParent = Cursor(tmp.tu, parent);
            auto r = tmp.dg(dCursor, dParent);
            tmp.returnCode = r;
            return r ? CXChildVisit_Break : CXChildVisit_Continue;
        }
    }

    static struct OpApplyData {
        int returnCode;
        Delegate dg;
        TranslationUnit tu;

        this(Delegate dg, TranslationUnit tu) {
            this.dg = dg;
            this.tu = tu;
        }
    }

    template Constructors() {
        private Visitor visitor;

        this(Visitor visitor) {
            this.visitor = visitor;
        }

        this(Cursor cursor) {
            visitor = Visitor(cursor);
        }
    }
}

struct DeclarationVisitor {
    mixin Visitor.Constructors;

    int opApply(Visitor.Delegate dg) {
        foreach (cursor, parent; visitor) {
            if (cursor.isDeclaration) {
                if (auto result = dg(cursor, parent)) {
                    return result;
                }
            }
        }

        return 0;
    }
}

struct TypedVisitor(CXCursorKind kind) {
    private Visitor visitor;

    this(Visitor visitor) {
        this.visitor = visitor;
    }

    this(Cursor cursor) {
        this.visitor = Visitor(cursor);
    }

    int opApply(Visitor.Delegate dg) {
        foreach (cursor, parent; visitor) {
            if (cursor.kind == kind) {
                if (auto result = dg(cursor, parent)) {
                    return result;
                }
            }
        }

        return 0;
    }
}

alias ObjCInstanceMethodVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCInstanceMethodDecl);
alias ObjCClassMethodVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCClassMethodDecl);
alias ObjCPropertyVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCPropertyDecl);
alias ObjCProtocolVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCProtocolRef);

struct ParamVisitor {
    mixin Visitor.Constructors;

    int opApply(int delegate(ref ParamCursor) dg) {
        foreach (cursor, parent; visitor) {
            if (cursor.kind == CXCursorKind.CXCursor_ParmDecl) {
                auto paramCursor = ParamCursor(cursor);

                if (auto result = dg(paramCursor))
                    return result;
            }
        }

        return 0;
    }

    @property size_t length() {
        auto type = Cursor(visitor.cursor).type;

        if (type.isValid)
            return type.func.arguments.length;

        else {
            size_t i;

            foreach (_; this)
                i++;

            return i;
        }
    }

    @property bool any() {
        return length > 0;
    }

    @property bool isEmpty() {
        return !any;
    }

    @property ParamCursor first() {
        assert(any, "Cannot get the first parameter of an empty parameter list");

        foreach (c; this)
            return c;

        assert(0, "Cannot get the first parameter of an empty parameter list");
    }
}

/** Determine the set of methods that are overridden by the given
 * method.
 *
 * In both Objective-C and C++, a method (aka virtual member function,
 * in C++) can override a virtual method in a base class. For
 * Objective-C, a method is said to override any method in the class's
 * base class, its protocols, or its categories' protocols, that has the same
 * selector and is of the same kind (class or instance).
 * If no such method exists, the search continues to the class's superclass,
 * its protocols, and its categories, and so on. A method from an Objective-C
 * implementation is considered to override the same methods as its
 * corresponding method in the interface.
 *
 * For C++, a virtual member function overrides any virtual member
 * function with the same signature that occurs in its base
 * classes. With multiple inheritance, a virtual member function can
 * override several virtual member functions coming from different
 * base classes.
 *
 * In all cases, this function determines the immediate overridden
 * method, rather than all of the overridden methods. For example, if
 * a method is originally declared in a class A, then overridden in B
 * (which in inherits from A) and also in C (which inherited from B),
 * then the only overridden method returned from this function when
 * invoked on C's method will be B's method. The client may then
 * invoke this function again, given the previously-found overridden
 * methods, to map out the complete method-override set.
 *
 * \param cursor A cursor representing an Objective-C or C++
 * method. This routine will compute the set of methods that this
 * method overrides.
 *
 * \param overridden A pointer whose pointee will be replaced with a
 * pointer to an array of cursors, representing the set of overridden
 * methods. If there are no overridden methods, the pointee will be
 * set to NULL. The pointee must be freed via a call to
 * \c clang_disposeOverriddenCursors().
 *
 * \param num_overridden A pointer to the number of overridden
 * functions, will be set to the number of overridden functions in the
 * array pointed to by \p overridden.
 */
struct OverriddenVisitor {
    alias Delegate = int delegate(ref Cursor);

    private Cursor cursor;

    this(Cursor cursor) {
        this.cursor = cursor;
    }

    int opApply(Delegate dg) {
        int result = 0;
        CXCursor* overridden;
        uint num_overridden;

        clang_getOverriddenCursors(this.cursor.cx, &overridden, &num_overridden);
        for (uint i = 0; i < num_overridden; ++overridden) {
            auto c = Cursor(*overridden);
            result = dg(c);
            if (result)
                break;
        }
        clang_disposeOverriddenCursors(overridden);

        return result;
    }
}
