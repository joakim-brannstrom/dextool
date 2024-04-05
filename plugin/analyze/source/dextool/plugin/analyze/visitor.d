/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.analyze.visitor;

import libclang_ast.ast : Visitor;
import dextool.type : AbsolutePath;

@safe:

/** Calculate McCabe per file and function.
*/
final class TUVisitor : Visitor {
    import std.string : startsWith;
    import dsrcgen.cpp;
    import libclang_ast.ast;
    import libclang_ast.cursor_logger : logNode, mixinNodeLog;
    import cpptooling.data.symbol : Container;

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
        string s = "override void visit(scope const " ~ node_t ~ " v) @trusted {\n";
        s ~= "auto callbacks = " ~ callback_member ~ ";";
        s ~= q{
            if (!v.cursor.location.path.startsWith(restrict.toString))
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
    this(AbsolutePath restrict) nothrow {
        this.restrict = restrict;
    }

    override void visit(scope const(TranslationUnit) v) {
        v.accept(this);
    }

    override void visit(scope const(Attribute) v) {
        v.accept(this);
    }

    override void visit(scope const(Declaration) v) {
        v.accept(this);
    }

    override void visit(scope const(Expression) v) {
        v.accept(this);
    }

    override void visit(scope const(Preprocessor) v) {
        v.accept(this);
    }

    override void visit(scope const(Reference) v) {
        v.accept(this);
    }

    override void visit(scope const(Statement) v) {
        v.accept(this);
    }
}
