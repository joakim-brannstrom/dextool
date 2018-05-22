/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Test cases in
See: test.component.generator
*/
module cpptooling.generator.gtest;

import std.range : isInputRange;

import dsrcgen.cpp : CppModule, E;

import dextool.type : FileName, DextoolVersion, CustomHeader;

import cpptooling.data : CppClass, FullyQualifiedNameType, TypeKindVariable;
import cpptooling.data.symbol : Container;

// argument names used in the generated code
private immutable argValue = "x0";
private immutable argStream = "os";

auto generateGtestHdr(FileName if_file, FileName incl_guard, DextoolVersion ver,
        CustomHeader custom_hdr, CppModule gtest) {
    import std.path : baseName;
    import dsrcgen.cpp : CppHModule;
    import cpptooling.generator.includes : convToIncludeGuard, makeHeader;

    auto o = CppHModule(convToIncludeGuard(incl_guard));
    o.header.append(makeHeader(incl_guard, ver, custom_hdr));
    o.content.include(if_file.baseName);
    o.content.include("gtest/gtest.h");
    o.content.sep(2);
    o.content.append(gtest);

    return o;
}

/** Generate a compare operator for use with EXPECT_EQ in gtest.
 *
 * Optimized compares using == for primitive types except floats.
 * Google tests internal helper for all others.
 */
void generateGtestPrettyEqual(T)(T members, const FullyQualifiedNameType name,
        string guard_prefix, ref const Container container, CppModule m) {
    import std.algorithm : map, among;
    import std.ascii : isAlphaNum;
    import std.conv : to;
    import std.format : format;
    import std.string : toUpper;
    import logger = std.experimental.logger;

    import cpptooling.data.kind : resolveTypeRef;
    import cpptooling.data : TypeKind, USRType, TypeAttr, isIncompleteArray;

    auto findType(USRType a) {
        return container.find!TypeKind(a);
    }

    static void fieldCompare(string field, TypeKind canonical_t, CppModule code) {
        if (canonical_t.info.kind == TypeKind.Info.Kind.primitive) {
            auto info = cast(TypeKind.PrimitiveInfo) canonical_t.info;
            // reuse google tests internal helper for floating points because it does an ULP*4
            if (info.fmt.typeId.among("float", "double", "long double")) {
                // long double do not work with the template thus reducing to a double
                code.stmt(format(
                        `acc = acc && ::testing::internal::CmpHelperFloatingPointEQ<%s>("", "", lhs.%s, rhs.%s)`,
                        info.fmt.typeId == "long double" ? "double" : info.fmt.typeId, field, field));
            } else {
                code.stmt(E("acc") = E("acc && " ~ format("lhs.%s == rhs.%s", field, field)));
            }
        } else {
            code.stmt(format(`acc = acc && ::testing::internal::CmpHelperEQ("", "", lhs.%s, rhs.%s)`,
                    field, field));
        }
    }

    auto ifndef = m.IFNDEF(format("%s_NO_CMP_%s", guard_prefix.toUpper,
            name.map!(a => a.isAlphaNum ? a : '_').map!(a => a.to!char)));

    auto func = ifndef.func_body("inline bool", "operator==",
            format("const %s& lhs, const %s& rhs", name, name));

    func.stmt("bool acc = true");

    foreach (mem; members) {
        TypeKind kind = mem.type.kind;
        auto canonical_t = resolveTypeRef(kind, &findType);

        // a constant array compares element vise. For now can only handle one dimensional arrays
        if (canonical_t.info.kind == TypeKind.Info.Kind.array
                && !isIncompleteArray(canonical_t.info.indexes)
                && canonical_t.info.indexes.length == 1) {
            auto elem_t = findType(canonical_t.info.element).front;
            auto canonical_elem_t = resolveTypeRef(elem_t, &findType);
            auto loop = func.for_("unsigned int dextool_i = 0",
                    "dextool_i < " ~ canonical_t.info.indexes[0].to!string, "++dextool_i");
            fieldCompare(mem.name ~ "[dextool_i]", canonical_elem_t, loop);
            with (loop.if_("!acc"))
                return_("false");
        } else {
            fieldCompare(mem.name, canonical_t, func);
        }
    }

    func.return_("acc");
    m.sep(2);
}

/** Generate Google Test pretty printers of a PODs public members.
 *
 * Params:
 *  src = POD to generate the pretty printer for.
 *  m = module to generate code in.
 */
void generateGtestPrettyPrintHdr(const FullyQualifiedNameType name, CppModule m) {
    import std.format : format;

    m.func("void", "PrintTo", format("const %s& %s, ::std::ostream* %s", name,
            argValue, argStream));
    m.sep(2);
}

/** Generate Google Test pretty printers of a PODs public members.
 *
 * This mean that the actual values are printed instead of the byte
 * representation.
 *
 * Params:
 *  members = range of the members to pretty print
 *  name = fqn name of the type that have the members
 *  m = module to generate code in.
 */
void generateGtestPrettyPrintImpl(T)(T members, const FullyQualifiedNameType name, CppModule m)
        if (isInputRange!T) {
    import std.algorithm;
    import std.format : format;

    auto func = m.func_body("void", "PrintTo",
            format("const %s& %s, ::std::ostream* %s", name, argValue, argStream));

    string space = null;
    foreach (mem; members) {
        func.stmt(E("*os <<") ~ E(format(`"%s%s:"`, space,
                mem.name)) ~ E("<<") ~ E("::testing::PrintToString")(E(argValue).E(mem.name)));
        space = " ";
    }

    m.sep(2);
}
