/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.analyze_helper;

import logger = std.experimental.logger;

import std.typecons : Nullable;

import cpptooling.analyzer.clang.ast : FunctionDecl, VarDecl;
import cpptooling.data.representation : CFunction, CxGlobalVariable;
import cpptooling.data.symbol.container : Container;

Nullable!CFunction analyzeFunctionDecl(const(FunctionDecl) v, ref Container container) @trusted
out (result) {
    logger.info(!result.isNull, "function: ", result.get.toString);
}
body {
    import std.algorithm : among;
    import std.functional : pipe;

    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.ast.visitor;
    import cpptooling.analyzer.clang.type : TypeKind, retrieveType,
        logTypeResult;
    import cpptooling.analyzer.clang.utility : put;
    import cpptooling.data.type : TypeResult, TypeKindAttr;
    import cpptooling.data.representation : CxParam, CFunctionName,
        CxReturnType, CFunction, VariadicType, LocationTag, StorageClass;
    import cpptooling.data.symbol.container : Container;

    // hint, start reading the function from the bottom up.
    // design is pipe and data transformation

    Nullable!TypeResult extractAndStoreRawType(Cursor c) {
        auto tr = retrieveType(c, container);
        if (tr.isNull) {
            return tr;
        }

        assert(tr.primary.kind.info.kind.among(TypeKind.Info.Kind.func,
                TypeKind.Info.Kind.typeRef, TypeKind.Info.Kind.simple));
        put(tr, container);

        return tr;
    }

    Nullable!TypeResult lookupRefToConcreteType(Nullable!TypeResult tr) {
        if (tr.isNull) {
            return tr;
        }

        if (tr.primary.kind.info.kind == TypeKind.Info.Kind.typeRef) {
            // replace typeRef kind with the func
            auto kind = container.find!TypeKind(tr.primary.kind.info.canonicalRef).front;
            tr.primary.kind = kind;
        }

        logTypeResult(tr);
        assert(tr.primary.kind.info.kind == TypeKind.Info.Kind.func);

        return tr;
    }

    static struct ComposeData {
        TypeResult tr;
        CFunctionName name;
        LocationTag loc;
        VariadicType isVariadic;
        StorageClass storageClass;
    }

    ComposeData getCursorData(TypeResult tr) {
        import deimos.clang.index : CX_StorageClass;
        import cpptooling.analyzer.clang.visitor : toInternal;

        auto data = ComposeData(tr);

        data.name = CFunctionName(v.cursor.spelling);
        data.loc = toInternal(v.cursor.location());

        switch (v.cursor.storageClass()) with (CX_StorageClass) {
        case CX_SC_Extern:
            data.storageClass = StorageClass.Extern;
            break;
        case CX_SC_Static:
            data.storageClass = StorageClass.Static;
            break;
        default:
            break;
        }

        return data;
    }

    Nullable!CFunction composeFunc(ComposeData data) {
        import cpptooling.analyzer.clang.visitor : toCxParam;

        Nullable!CFunction rval;

        auto return_type = container.find!TypeKind(data.tr.primary.kind.info.return_);
        if (auto return_type.length == 0) {
            return rval;
        }

        auto params = toCxParam(data.tr, container);

        VariadicType is_variadic;
        // according to C/C++ standard the last parameter is the only one
        // that can be a variadic, therefor only needing to peek at that
        // one.
        if (params.length > 0 && params[$ - 1].peek!VariadicType) {
            is_variadic = VariadicType.yes;
        }

        rval = CFunction(data.name, params, CxReturnType(TypeKindAttr(return_type.front,
                data.tr.primary.kind.info.returnAttr)), is_variadic, data.storageClass, data.loc);
        return rval;
    }

    // dfmt off
    auto rval = pipe!(extractAndStoreRawType,
                      lookupRefToConcreteType,
                      // either break early if null or continue composing a
                      // function representation
                      (Nullable!TypeResult tr) {
                          if (tr.isNull) {
                              return Nullable!CFunction();
                          } else {
                              return pipe!(getCursorData, composeFunc)(tr.get);
                          }
                      }
                      )
        (v.cursor);
    // dfmt on

    return rval;
}

CxGlobalVariable analyzeVarDecl(const(VarDecl) v, ref Container container)
out (result) {
    logger.info("variable:", result.toString);
}
body {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.type : retrieveType;
    import cpptooling.analyzer.clang.utility : put;
    import cpptooling.analyzer.clang.visitor : toInternal;
    import cpptooling.data.representation : CppVariable;

    Cursor c = v.cursor;
    auto type = retrieveType(c, container);
    put(type, container);

    auto name = CppVariable(v.cursor.spelling);
    auto loc = toInternal(v.cursor.location());

    return CxGlobalVariable(type.primary, name, loc);
}
