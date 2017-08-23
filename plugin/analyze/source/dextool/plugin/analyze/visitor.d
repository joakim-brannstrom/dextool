/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.analyze.visitor;

import cpptooling.analyzer.clang.ast : Visitor;
import dextool.type : FileName, AbsolutePath;

@safe:

/** Calculate McCabe per file and function.
*/
final class TUVisitor : Visitor {
    import std.string : startsWith;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.data.symbol : Container;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.cpp;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    alias CallbackT(T) = void delegate(const(T) v) @safe;

    private static string makeCallback(string kind) {
        string s;
        string alias_name = "On" ~ kind ~ "T";
        s = "alias " ~ alias_name ~ " = CallbackT!" ~ kind ~ ";\n";
        s ~= alias_name ~ "[] on" ~ kind ~ ";\n";
        return s;
    }

    private static string makeCallbacks(Kinds...)() {
        string s;
        foreach (k; Kinds)
            s ~= makeCallback(k.stringof);
        return s;
    }

    // note that it requires a member variable called restrict
    private static string makeVisitor(string node_t, string callback_member) {
        string s = "override void visit(const(" ~ node_t ~ ") v) {\n";
        s ~= "auto callbacks = " ~ callback_member ~ ";";
        s ~= q{
            if (!v.cursor.location.path.startsWith(restrict))
                return;
            foreach (c; callbacks)
                c(v);
            v.accept(this);
        };

        s ~= "}\n";
        return s;
    }

    private static string makeVisitors(Kinds...)() {
        string s;
        foreach (k; Kinds) {
            s ~= makeVisitor(k.stringof, "on" ~ k.stringof);
        }
        return s;
    }

    import std.meta : AliasSeq;

    private alias callbackKinds = AliasSeq!(FunctionDecl, Constructor,
            Destructor, CXXMethod, ConversionFunction, FunctionTemplate, ClassTemplate);

    // debugging
    //pragma(msg, makeCallbacks!callbackKinds);
    //pragma(msg, makeVisitors!callbackKinds);

    mixin(makeCallbacks!(callbackKinds));
    mixin(makeVisitors!(callbackKinds));

    private AbsolutePath restrict;

    /**
     * Params:
     *  restrict = only analyze files starting with this path
     */
    this(AbsolutePath restrict) {
        this.restrict = restrict;
    }

    override void visit(const(TranslationUnit) v) {
        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        v.accept(this);
    }

    override void visit(const(Directive) v) {
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        v.accept(this);
    }

    override void visit(const(Preprocessor) v) {
        v.accept(this);
    }

    override void visit(const(Reference) v) {
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        v.accept(this);
    }
}
