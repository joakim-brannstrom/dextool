/**
 * Copyright: Copyright (c) 2012 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 29, 2012
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module clang.Visitor;

import deimos.clang.index;

import clang.Cursor;
import clang.TranslationUnit;

struct Visitor {
    alias Delegate = int delegate(ref Cursor, ref Cursor);
    alias OpApply = int delegate(Delegate dg);

@safe:

    private CXCursor cursor;

    this(CXCursor cursor) {
        this.cursor = cursor;
    }

    this(Cursor cursor) {
        this.cursor = cursor.cx;
    }

    /**
     * Trusted: assuming the LLVM function do NOT abuse the pointer in any way.
     */
    int opApply(Delegate dg) @trusted {
        if (dg is null)
            return 0;

        auto data = OpApplyData(dg);
        clang_visitChildren(cursor, &visitorFunction, cast(CXClientData)&data);

        return data.returnCode;
    }

    /**
     * Trusted: assuming the LLVM function do NOT abuse the pointer in any way.
     */
    int opApply(int delegate(ref Cursor) dg) @trusted {
        int wrapper(ref Cursor cursor, ref Cursor) {
            return dg(cursor);
        }

        if (dg is null)
            return 0;

        auto data = OpApplyData(&wrapper);
        clang_visitChildren(cursor, &visitorFunction, cast(CXClientData)&data);

        return data.returnCode;
    }

private:

    extern (C) static CXChildVisitResult visitorFunction(CXCursor cursor,
            CXCursor parent, CXClientData data) @trusted {
        if (data is null)
            return CXChildVisitResult.CXChildVisit_Continue;

        auto tmp = cast(OpApplyData*) data;

        with (CXChildVisitResult) {
            auto dCursor = Cursor(cursor);
            auto dParent = Cursor(parent);
            auto r = tmp.dg(dCursor, dParent);
            tmp.returnCode = r;
            return r ? CXChildVisit_Break : CXChildVisit_Continue;
        }
    }

    static struct OpApplyData {
        int returnCode;
        Delegate dg;

        this(Delegate dg) {
            this.dg = dg;
        }
    }

    template Constructors() {
        private Visitor visitor;

        this(Visitor visitor) {
            this.visitor = visitor;
        }

        this(CXCursor cursor) {
            visitor = Visitor(cursor);
        }

        this(Cursor cursor) {
            visitor = Visitor(cursor);
        }
    }
}

@safe struct InOrderVisitor {
    alias int delegate(ref Cursor, ref Cursor) Delegate;

    private Cursor cursor;

    this(CXCursor cursor) {
        this.cursor = Cursor(cursor);
    }

    this(Cursor cursor) {
        this.cursor = cursor;
    }

    int opApply(Delegate dg) @trusted {
        import std.array;

        auto visitor = Visitor(cursor);
        int result = 0;

        auto macrosAppender = appender!(Cursor[])();
        size_t itr = 0;

        foreach (cursor, _; visitor) {
            if (cursor.isPreprocessing)
                macrosAppender.put(cursor);
        }

        auto macros = macrosAppender.data;
        auto query = cursor.translationUnit.relativeLocationAccessorImpl(macros);

        ulong macroIndex = macros.length != 0 ? query(macros[0].location) : ulong.max;

        size_t jtr = 0;

        foreach (cursor, parent; visitor) {
            if (!cursor.isPreprocessing) {
                ulong cursorIndex = query(cursor.location);

                while (macroIndex < cursorIndex) {
                    Cursor macroParent = macros[jtr].semanticParent;

                    result = dg(macros[jtr], macroParent);

                    if (result)
                        return result;

                    ++jtr;

                    macroIndex = jtr < macros.length ? query(macros[jtr].location) : ulong.max;
                }

                result = dg(cursor, parent);

                if (result)
                    return result;
            }
        }

        while (jtr < macros.length) {
            Cursor macroParent = macros[jtr].semanticParent;

            result = dg(macros[jtr], macroParent);

            if (result)
                return result;

            ++jtr;
        }

        return result;
    }

private:

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
