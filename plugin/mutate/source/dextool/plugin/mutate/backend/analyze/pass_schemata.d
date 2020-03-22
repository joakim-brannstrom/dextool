/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.pass_schemata;

import logger = std.experimental.logger;
import std.algorithm : among, map, sort, filter;
import std.array : appender, empty, array, Appender;
import std.exception : collectException;
import std.format : formattedWrite;
import std.meta : AliasSeq;
import std.range : retro, ElementType;
import std.typecons : Nullable, tuple, Tuple, scoped;

import automem : vector, Vector;

import clang.Cursor : Cursor;
import clang.Eval : Eval;
import clang.Type : Type;
import clang.c.Index : CXTypeKind, CXCursorKind, CXEvalResultKind, CXTokenKind;

import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

import dextool.clang_extensions : getUnderlyingExprNode;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast : Interval, Location;
import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.internal;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.database : MutationPointEntry, MutationPointEntry2;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset, Mutation, SourceLocRange;

import analyze = dextool.plugin.mutate.backend.analyze.ast;

@safe:

/// Translate a mutation AST to a schemata.
void toSchemata(ref analyze.Ast ast) @safe {
    auto visitor = () @trusted { return new SchemataVisitor(&ast); }();
    ast.accept(visitor);
}

private:

class SchemataVisitor : analyze.DepthFirstVisitor {
    analyze.Ast* ast;

    this(analyze.Ast* ast) {
        this.ast = ast;
    }
}
