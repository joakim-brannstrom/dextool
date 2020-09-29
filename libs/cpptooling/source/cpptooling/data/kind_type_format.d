/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Type safe formatters for C/C++ types.

Every formatter that have a TypeIdLR have a toString method that take a left
and right writer. Those are used to compose formatters.
Shift to the right writer after declaration-id is written.

Example of types this module must be able to handle:
int x
void x(int)
int *x
void (*x)(int)
void (*const x)(int)
int const* x
int *const x
int x[3]
*/
module cpptooling.data.kind_type_format;

version (unittest) {
    import unit_threaded : shouldEqual;
}

@safe struct Left {
    string payload;
    alias payload this;
}

@safe struct Right {
    string payload;
    alias payload this;
}

/// type-id
@safe struct TypeId {
    string payload;
    alias payload this;
}

/// type-id where the declaration-id is in between two blocks
@safe struct TypeIdLR {
    Left left;
    Right right;
}

/// declaration-id
@safe struct DeclId {
    string payload;
    alias payload this;
}

/// cv-qualifier such as const/volatile
@safe struct CvQ {
    enum Kind {
        none,
        const_,
        volatile_
    }

    Kind payload;
    alias payload this;

    static auto const_() @safe {
        return CvQ(Kind.const_);
    }

    static auto volatile_() @safe {
        return CvQ(Kind.volatile_);
    }

    void toString(Writer)(scope Writer w) const {
        import std.range.primitives : put;

        final switch (payload) {
        case Kind.none:
            break;
        case Kind.const_:
            put(w, "const");
            break;
        case Kind.volatile_:
            put(w, "volatile");
            break;
        }
    }
}

/// ptr-qualifier such as */&.
@safe struct PtrQ {
    /// Kind of pointer
    enum Kind {
        ptr,
        ref_
    }

    Kind payload;
    alias payload this;

    static auto ptr() @safe {
        return PtrQ(Kind.ptr);
    }

    static auto ref_() @safe {
        return PtrQ(Kind.ref_);
    }

    void toString(Writer)(scope Writer w) const {
        import std.range.primitives : put;

        final switch (payload) {
        case Kind.ptr:
            put(w, "*");
            break;
        case Kind.ref_:
            put(w, "&");
            break;
        }
    }
}

/// Pair of ptr-qualifier and cv-qualifier.
@safe struct CvPtrQ {
    CvQ cvQual;
    PtrQ ptrQual;
}

/// Size of an array.
@safe struct ArraySize {
    enum Kind {
        dynamic,
        const_,
    }

    static struct Size {
        Kind kind;
        long payload;
        alias payload this;
    }

    Size[] payload;
    alias payload this;
}

@safe struct SimpleFmt {
    TypeId typeId;

    this(TypeId typeId) pure nothrow {
        this.typeId = typeId;
    }

    void toString(Writer)(scope Writer w, CvQ cv_qual, DeclId decl_id) const {
        import std.range.primitives : put;

        if (cv_qual != CvQ.Kind.none) {
            cv_qual.toString(w);
            put(w, " ");
        }

        put(w, typeId);

        if (decl_id.length > 0) {
            put(w, " ");
            put(w, decl_id);
        }
    }
}

@("A simple type formatted with and without decl-id")
@safe unittest {
    auto simple = SimpleFmt(TypeId("int"));

    {
        char[] buf;
        simple.toString((const(char)[] s) { buf ~= s; }, CvQ(), DeclId(null));
        buf.shouldEqual("int");
    }

    {
        char[] buf;
        simple.toString((const(char)[] s) { buf ~= s; }, CvQ(), DeclId("x"));
        buf.shouldEqual("int x");
    }

    {
        char[] buf;
        simple.toString((const(char)[] s) { buf ~= s; }, CvQ.const_, DeclId("y"));
        buf.shouldEqual("const int y");
    }
}

@safe struct ArrayFmt {
    TypeIdLR typeId;

    this(TypeId typeId) pure nothrow {
        this.typeId.left = Left(typeId);
    }

    this(TypeIdLR typeId) pure nothrow {
        this.typeId = typeId;
    }

    void toString(WriterL, WriterR)(scope WriterL wl, scope WriterR wr, CvQ cv_qual,
            DeclId decl_id, ArraySize sz) const {
        import std.conv : to;
        import std.range.primitives : put;

        if (cv_qual != CvQ.Kind.none) {
            cv_qual.toString(wl);
            put(wl, " ");
        }

        put(wl, typeId.left);

        if (decl_id.length > 0) {
            put(wl, " ");
            put(wl, decl_id);
        }

        put(wr, typeId.right);

        foreach (ind; sz) {
            put(wr, "[");
            final switch (ind.kind) {
            case ArraySize.Kind.const_:
                put(wr, ind.payload.to!string);
                break;
            case ArraySize.Kind.dynamic:
                break;
            }
            put(wr, "]");
        }
    }
}

@("An array type formatted")
@safe unittest {
    auto arr = ArrayFmt(TypeId("int"));

    { // simplest case
        char[] buf;
        arr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        }, CvQ(), DeclId("x"), ArraySize([ArraySize.Size()]));
        buf.shouldEqual("int x[]");
    }

    { // const
        char[] buf;
        arr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        }, CvQ.const_, DeclId("x"), ArraySize([ArraySize.Size()]));
        buf.shouldEqual("const int x[]");
    }

    { // array with static value
        char[] buf;
        arr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        }, CvQ(), DeclId("x"), ArraySize([
                    ArraySize.Size(ArraySize.Kind.const_, 42)
                ]));
        buf.shouldEqual("int x[42]");
    }

    { // combine static array with dynamic
        char[] buf;
        arr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        }, CvQ(), DeclId("x"), ArraySize([
                    ArraySize.Size(), ArraySize.Size(ArraySize.Kind.const_, 42)
                ]));
        buf.shouldEqual("int x[][42]");
    }
}

@safe struct PtrFmt {
    TypeIdLR typeId;

    this(TypeId typeId) pure nothrow {
        this.typeId.left = Left(typeId);
    }

    this(TypeIdLR typeId) pure nothrow {
        this.typeId = typeId;
    }

    void toString(WriterL, WriterR)(scope WriterL wl, scope WriterR wr, CvQ cv_qual,
            CvPtrQ[] cv_ptr_quals, DeclId decl_id) const {
        import std.range.primitives : put;

        if (cv_qual != CvQ.Kind.none) {
            cv_qual.toString(wl);
            put(wl, " ");
        }

        put(wl, typeId.left);

        if (cv_ptr_quals.length > 0) {
            put(wl, " ");
        }

        foreach (q; cv_ptr_quals) {
            q.ptrQual.toString(wl);
            q.cvQual.toString(wl);
        }

        if (decl_id.length > 0 && cv_ptr_quals.length > 0
                && cv_ptr_quals[$ - 1].cvQual != CvQ.Kind.none) {
            put(wl, " ");
        }
        put(wl, decl_id);

        put(wr, typeId.right);
    }
}

version (unittest) {
    @("A PtrFmt in its basic shapes")
    unittest {
        foreach (kind; [PtrQ.Kind.ptr, PtrQ.Kind.ref_]) {
            auto ptr = PtrFmt(TypeId("int"));

            string kstr;
            final switch (kind) {
            case PtrQ.Kind.ref_:
                kstr = "&";
                break;
            case PtrQ.Kind.ptr:
                kstr = "*";
                break;
            }

            { // simplest
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ(), null, DeclId(null));
                buf.shouldEqual("int");
            }

            { // simples ptr
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ(), [CvPtrQ(CvQ(), PtrQ(kind))], DeclId("x"));
                buf.shouldEqual("int " ~ kstr ~ "x");
            }

            { // simples head const ptr
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ.const_, [CvPtrQ(CvQ.const_, PtrQ(kind))], DeclId("x"));
                buf.shouldEqual("const int " ~ kstr ~ "const x");
            }

            { // ptr with varying cv-qualifier
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ.const_, [// dfmt off
                     CvPtrQ(CvQ.const_, PtrQ(kind)),
                     CvPtrQ(CvQ(), PtrQ(kind)),
                     CvPtrQ(CvQ.const_, PtrQ(kind)),
                     CvPtrQ(CvQ(), PtrQ(kind)),
                     CvPtrQ(CvQ(), PtrQ(kind)),
                     // dfmt on
                        ], DeclId("x"));
                buf.shouldEqual("const int " ~ kstr ~ "const" ~ kstr ~ kstr
                        ~ "const" ~ kstr ~ kstr ~ "x");
            }
        }
    }
}

@safe struct FuncPtrFmt {
    TypeIdLR typeId;

    this(TypeIdLR typeId) pure nothrow {
        this.typeId = typeId;
    }

    void toString(WriterL, WriterR)(scope WriterL wl, scope WriterR wr, CvQ cv_qual,
            CvPtrQ[] cv_ptr_quals, DeclId decl_id) const {
        import std.range.primitives : put;

        put(wl, typeId.left);

        if (cv_qual != CvQ.Kind.none) {
            cv_qual.toString(wl);
        }

        foreach (cq; cv_ptr_quals) {
            cq.ptrQual.toString(wl);
            cq.cvQual.toString(wl);
        }

        if (decl_id.length > 0 && cv_ptr_quals.length > 0
                && cv_ptr_quals[$ - 1].cvQual != CvQ.Kind.none) {
            put(wl, " ");
        }
        put(wl, decl_id);

        put(wr, typeId.right);
    }
}

version (unittest) {
    @("A FuncPtrFmt")
    unittest {
        foreach (kind; [PtrQ.Kind.ptr, PtrQ.Kind.ref_]) {
            auto ptr = FuncPtrFmt(TypeIdLR(Left("void ("), Right(")(int)")));

            string kstr;
            final switch (kind) {
            case PtrQ.Kind.ref_:
                kstr = "&";
                break;
            case PtrQ.Kind.ptr:
                kstr = "*";
                break;
            }

            { // simplest
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ(), null, DeclId(null));
                buf.shouldEqual("void ()(int)");
            }

            { // simples ptr
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ(), [CvPtrQ(CvQ(), PtrQ(kind))], DeclId("x"));
                buf.shouldEqual("void (" ~ kstr ~ "x)(int)");
            }

            { // simples head const ptr
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ.const_, [CvPtrQ(CvQ.const_, PtrQ(kind))], DeclId("x"));
                buf.shouldEqual("void (const" ~ kstr ~ "const x)(int)");
            }

            { // ptr with varying cv-qualifier
                char[] buf;
                ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
                    buf ~= s;
                }, CvQ.const_, [// dfmt off
                     CvPtrQ(CvQ.const_, PtrQ(kind)),
                     CvPtrQ(CvQ(), PtrQ(kind)),
                     CvPtrQ(CvQ.const_, PtrQ(kind)),
                     CvPtrQ(CvQ(), PtrQ(kind)),
                     CvPtrQ(CvQ(), PtrQ(kind)),
                     // dfmt on
                        ], DeclId("x"));
                buf.shouldEqual(
                        "void (const" ~ kstr ~ "const" ~ kstr ~ kstr ~ "const"
                        ~ kstr ~ kstr ~ "x)(int)");
            }
        }
    }
}

@safe struct FuncFmt {
    TypeIdLR typeId;

    this(TypeIdLR typeId) pure nothrow {
        this.typeId = typeId;
    }

    void toString(WriterL, WriterR)(scope WriterL wl, scope WriterR wr, DeclId decl_id) const {
        import std.range.primitives : put;

        put(wl, typeId.left);

        put(wl, " ");

        if (decl_id.length > 0) {
            put(wl, decl_id);
        }

        put(wr, typeId.right);
    }
}

@("A FuncFmt")
unittest {
    auto ptr = FuncFmt(TypeIdLR(Left("void"), Right("(int)")));

    { // simplest
        char[] buf;
        ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        }, DeclId(null));
        buf.shouldEqual("void (int)");
    }

    { // simples ptr
        char[] buf;
        ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        }, DeclId("x"));
        buf.shouldEqual("void x(int)");
    }
}

@safe struct FuncSignatureFmt {
    TypeIdLR typeId;

    this(TypeIdLR typeId) pure nothrow {
        this.typeId = typeId;
    }

    void toString(WriterL, WriterR)(scope WriterL wl, scope WriterR wr) const {
        import std.range.primitives : put;

        put(wl, typeId.left);
        put(wl, " ");
        put(wr, typeId.right);
    }
}

@("A FuncFmt")
unittest {
    auto ptr = FuncSignatureFmt(TypeIdLR(Left("void"), Right("(int)")));

    { // simplest
        char[] buf;
        ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        });
        buf.shouldEqual("void (int)");
    }

    { // simples ptr
        char[] buf;
        ptr.toString((const(char)[] s) { buf ~= s; }, (const(char)[] s) {
            buf ~= s;
        });
        buf.shouldEqual("void (int)");
    }
}

@safe struct CtorFmt {
    TypeId typeId;

    this(TypeId typeId) pure nothrow {
        this.typeId = typeId;
    }

    void toString(Writer)(scope Writer w, DeclId decl_id) const {
        import std.range.primitives : put;

        put(w, decl_id);
        put(w, typeId);
    }
}

@safe struct DtorFmt {
    void toString(Writer)(scope Writer w, DeclId decl_id) const {
        import std.range.primitives : put;

        put(w, "~");
        put(w, decl_id);
        put(w, "()");
    }
}
