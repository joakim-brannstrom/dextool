/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains helpers for creating types.
The general pattern used are builders that can be composed.
*/
module cpptooling.data.type_builder;

import std.typecons : Yes, No, Flag;

import cpptooling.data.kind;
import cpptooling.data.kind_type;
import cpptooling.data.kind_type_format;

version (unittest) {
    import unit_threaded : shouldEqual, Values, getValue;
}

//TODO remove, this is not good. keep it focused on SimleInfo.
TypeKindAttr makeSimple(string txt, TypeAttr attr = TypeAttr.init) pure @safe nothrow {
    import cpptooling.data : SimpleFmt, TypeId;

    TypeKind t;
    t.info = TypeKind.SimpleInfo(SimpleFmt(TypeId(txt)));

    return TypeKindAttr(t, attr);
}

struct BuildAttr {
    private TypeAttr attr;

    auto done() {
        return attr;
    }
}

struct BuildTypeKindAttr {
    private TypeKind kind;
    private TypeAttr attr;

    auto isConst(bool v) {
        attr.isConst = cast(Flag!"isConst") v;
        return this;
    }

    auto isRef(bool v) {
        attr.isRef = cast(Flag!"isRef") v;
        return this;
    }

    auto isPtr(bool v) {
        attr.isPtr = cast(Flag!"isPtr") v;
        return this;
    }

    auto isFuncPtr(bool v) {
        attr.isFuncPtr = cast(Flag!"isFuncPtr") v;
        return this;
    }

    auto isArray(bool v) {
        attr.isArray = cast(Flag!"isArray") v;
        return this;
    }

    auto isDefinition(bool v) {
        attr.isDefinition = cast(Flag!"isDefinition") v;
        return this;
    }

    auto done() {
        return TypeKindAttr(kind, attr);
    }
}

auto buildAttr(T)(T kind) {
    return BuildTypeKindAttr(kind.done);
}

struct BuildNull {
}

struct BuildPrimitive {
    private TypeId type_;

    auto type(string v) {
        type_ = TypeId(v);
        return this;
    }

    auto done() {
        return TypeKind(TypeKind.SimpleInfo(SimpleFmt(type_)));
    }
}

struct BuildSimple {
    private TypeId type_;

    auto type(string v) {
        type_ = TypeId(v);
        return this;
    }

    auto done() {
        return TypeKind(TypeKind.SimpleInfo(SimpleFmt(type_)));
    }
}

struct BuildArray {
}

struct BuildFunc {
}

struct BuildFuncPtr {
}

struct BuildFuncSignature {
}

struct BuildRecord {
}

struct BuildCtor {
}

struct BuildDtor {
}

struct BuildPointer {
}

struct BuildTypeRef {
}

auto buildKind(TypeKind.Info.Kind kind)() {
    static if (kind == TypeKind.Info.Kind.null_) {
        return BuildNull();
    } else static if (kind == TypeKind.Info.Kind.primitive) {
        return BuildPrimitive();
    } else static if (kind == TypeKind.Info.Kind.simple) {
        return BuildSimple();
    } else static if (kind == TypeKind.Info.Kind.array) {
        return BuildArray();
    } else static if (kind == TypeKind.Info.Kind.func) {
        return BuildFunc();
    } else static if (kind == TypeKind.Info.Kind.funcPtr) {
        return BuildFuncPtr();
    } else static if (kind == TypeKind.Info.Kind.funcSignature) {
        return BuildFuncSignature();
    } else static if (kind == TypeKind.Info.Kind.record) {
        return BuildRecord();
    } else static if (kind == TypeKind.Info.Kind.ctor) {
        return BuildCtor();
    } else static if (kind == TypeKind.Info.Kind.dtor) {
        return BuildDtor();
    } else static if (kind == TypeKind.Info.Kind.pointer) {
        return BuildPointer();
    } else static if (kind == TypeKind.Info.Kind.typeRef) {
        return BuildTypeRef();
    } else {
        static assert(0, "Build kind " ~ kind.stringof ~ " not supported");
    }
}

@("shall instantiate all build kinds")
unittest {
    import std.traits : EnumMembers;

    foreach (k; EnumMembers!(TypeKind.Info.Kind)) {
        auto a = buildKind!k;
    }
}

@("shall be a primitive kind")
unittest {
    TypeKindAttr a = buildKind!(TypeKind.Info.Kind.simple).type("x").buildAttr.isConst(true).done;
}

@("shall be a simple kind")
unittest {
    TypeKindAttr a = buildKind!(TypeKind.Info.Kind.simple).type("x").buildAttr.isConst(true).done;
}
