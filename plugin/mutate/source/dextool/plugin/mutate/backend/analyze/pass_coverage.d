/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.pass_coverage;

import logger = std.experimental.logger;
import std.algorithm : among, map, sort, filter;
import std.array : appender, empty, array, Appender;
import std.exception : collectException;
import std.format : formattedWrite;
import std.range : retro, ElementType;
import std.typecons : tuple, Tuple, scoped;

import my.gc.refc : RefCounted;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.analyze.ast;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.type : Offset, Mutation, SourceLocRange, Token;

@safe:

CoverageResult toCoverage(RefCounted!Ast ast, FilesysIO fio, ValidateLoc vloc) {
    auto visitor = new CoverageVisitor(ast, fio, vloc);
    scope (exit)
        visitor.dispose;
    ast.accept(visitor);
    return visitor.result;
}

/// Find all places to instrument.
class CoverageResult {
    Interval[][AbsolutePath] points;

    private {
        FilesysIO fio;
        ValidateLoc vloc;
    }

    this(FilesysIO fio, ValidateLoc vloc) {
        this.fio = fio;
        this.vloc = vloc;
    }

    override string toString() @safe {
        import std.format : formattedWrite;
        import std.range : put;

        auto w = appender!string;

        put(w, "CoverageResult\n");
        foreach (f; points.byKeyValue) {
            formattedWrite(w, "%s\n", f.key);
            foreach (p; f.value) {
                formattedWrite(w, "  %s\n", p);
            }
        }

        return w.data;
    }

    private void put(const AbsolutePath p) {
        if (!vloc.shouldMutate(p) || p in points)
            return;
        points[p] = Interval[].init;
    }

    private void put(const AbsolutePath p, const Interval i) {
        if (auto v = p in points) {
            *v ~= i;
        }
    }
}

private:

class CoverageVisitor : DepthFirstVisitor {
    RefCounted!Ast ast;
    CoverageResult result;

    private {
        uint depth;
        Stack!(Kind) visited;
    }

    override void visitPush(Node n) {
        visited.put(n.kind, ++depth);
    }

    override void visitPop(Node n) {
        visited.pop;
        --depth;
    }

    alias visit = DepthFirstVisitor.visit;

    this(RefCounted!Ast ast, FilesysIO fio, ValidateLoc vloc) {
        this.ast = ast;
        result = new CoverageResult(fio, vloc);

        // by adding the locations here the rest of the visitor do not have to
        // be concerned about adding files.
        foreach (ref l; ast.locs.byValue) {
            result.put(l.file);
        }
    }

    void dispose() {
        ast.release;
    }

    override void visit(Function n) {
        if (n.blacklist || n.schemaBlacklist)
            return;
        accept(n, this);
    }

    override void visit(Block n) {
        if (visited[$ - 1].data != Kind.Function || n.blacklist || n.schemaBlacklist)
            return;

        const l = ast.location(n);
        // skip empty bodies. it is both not needed to instrument them because
        // they do not contain any mutants and there is a off by one bug that
        // sometimes occur wherein the instrumented function call is injected
        // before the braket, {.
        if (l.interval.begin == l.interval.end) {
            return;
        }
        result.put(l.file, l.interval);
    }
}
