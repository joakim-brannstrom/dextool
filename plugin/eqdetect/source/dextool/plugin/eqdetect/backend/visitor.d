/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the functionality of traversing the given file using Visitors
and the AST imported from clang. It searches the current visiting node for the mutant
and if found (in the interval of the current cursor) it extracts the code using SnippetFinder
and generates code in the form of text by using the dsrcgen library.

TODO:
- Utilize more of the visited statements and declaration for finding all mutants.
- Track dependencies and use SnippetFinder for extracting them.
*/

module dextool.plugin.eqdetect.backend.visitor;

import clang.Cursor;
import cpptooling.analyzer.clang.ast : Visitor;
import dextool.plugin.mutate.backend.type : Offset;

@safe:

final class TUVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.c : CModule;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;
    CModule generatedSource;
    CModule generatedMutation;
    CModule generatedSourceHeader;
    CModule generatedMutationHeader;

    bool generated = false;
    string function_name;
    string[] function_params;
    bool isFunctionVoid;
    Cursor[] semanticParentList;
    string[] types;

    Offset includeOffset;
    Offset[] offsets;
    Offset[] headerOffsets;

    import dextool.plugin.eqdetect.backend : Mutation;

    Mutation mutation;

    this(Mutation m) {
        this.generatedSource = new CModule();
        this.generatedMutation = new CModule();
        this.generatedSourceHeader = new CModule();
        this.generatedMutationHeader = new CModule();
        this.mutation = m;
        this.includeOffset.begin = -1;
        this.includeOffset.end = -1;
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        import std.path : extension;
        import dextool.plugin.eqdetect.backend : SnippetFinder;
        if(extension(v.cursor.extent.path) == ".cpp"){
            auto s = SnippetFinder.generateSource(v.cursor, this.mutation);
            generatedSource.text(s);
        }
        else if(extension(v.cursor.extent.path) == ".hpp"){
            auto s = SnippetFinder.generateSource(v.cursor, this.mutation);
            generatedSourceHeader.text(s);
        }

        v.accept(this);
    }


    override void visit(const(TypedefDecl) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());

        checkTypes(v.cursor);
        v.accept(this);
    }

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());
        checkTypes(v.cursor);
        v.accept(this);
    }

    override void visit(const(ParmDecl) v) {
        mixin(mixinNodeLog!());
        checkTypes(v.cursor);
        v.accept(this);
    }

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());
        checkTypes(v.cursor);
        v.accept(this);
    }


    override void visit(const(CxxMethod) v) {
        mixin(mixinNodeLog!());
        checkTypes(v.cursor);
        saveMutationInformation(v.cursor);
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());
        checkTypes(v.cursor);
        saveMutationInformation(v.cursor);
        v.accept(this);
    }

    // To avoid namechange of for example 'public:'
    override void visit(const(CxxAccessSpecifier) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(ClassDecl) v) {
        mixin(mixinNodeLog!());
        saveTypes(v.cursor);
        checkTypes(v.cursor);
        v.accept(this);
    }

    override void visit(const(StructDecl) v) {
        mixin(mixinNodeLog!());
        saveTypes(v.cursor);
        checkTypes(v.cursor);
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        checkTypes(v.cursor);
        v.accept(this);
    }


    override void visit(const(MemberRefExpr) v) {
        mixin(mixinNodeLog!());
        checkTypes(v.cursor);
        v.accept(this);
    }

    override void visit(const(Directive) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(InclusionDirective) v) {
        mixin(mixinNodeLog!());
        if(isSameBaseName(mutation.path, v.cursor.spelling)){
            saveOffsets(v.cursor);
        }
        v.accept(this);
    }

    override void visit(const(Preprocessor) v) {
        mixin(mixinNodeLog!());
        import std.path : stripExtension;
        if(stripExtension(v.cursor.extent.path) == stripExtension(mutation.path)){
            checkTypes(v.cursor);
        }
        v.accept(this);
    }

    override void visit(const(Reference) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }



    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    bool isSameBaseName(string a, string b){
        import std.path: stripExtension, baseName;
        return stripExtension(baseName(a)) == stripExtension(baseName(b));
    }

    bool mutationInInterval(Cursor c) {
        return ((c.extent.end.offset >= mutation.offset.end) && (c.extent.start.offset <= mutation.offset.begin));
    }

    void saveTypes(Cursor c){
        import std.path : buildNormalizedPath, stripExtension;
        if(stripExtension(c.extent.path) == stripExtension(mutation.path)){
            types ~= c.spelling;
        }
    }

    @trusted void checkTypes(Cursor c){
        foreach(t;c.tokens){
            import std.algorithm: canFind;

            if (types.canFind(t.spelling)) {
                saveOffsets(c, t.spelling);
            }
        }
        saveOffsets(c);
    }

    @trusted Offset findOffset(Cursor c, string name){
        Offset offset;
        import std.stdio : File;
        import std.file : getSize;
        import std.string : indexOf;

        offset.begin = -1;
        offset.end = -1;

        foreach (token; c.tokens){
            // Handles both types and includes of files
            if (token.spelling == name || token.spelling == ("\"" ~ name ~ "\"") ){
                offset.begin = token.extent.start.offset;
                offset.end = token.extent.end.offset;

                return offset;
            }
        }
        return offset;
    }

    void saveOffsets(Cursor c, string name = "") {
        import std.path: extension;

        if (name == ""){name = c.spelling;}

        if (isSameBaseName(c.extent.path, mutation.path)){
            Offset offset = findOffset(c, name);

            if(offset.begin != -1 && offset.end != -1){
                import std.algorithm: canFind;
                import std.path : extension;
                import clang.c.Index;

                if(c.kind == CXCursorKind.inclusionDirective){
                    includeOffset = offset;
                }
                else if(extension(c.extent.path) == ".cpp"){
                    if (!offsets.canFind(offset)) {
                        offsets ~= offset;
                    }
                }
                else if(extension(c.extent.path) == ".hpp"){
                    if (!headerOffsets.canFind(offset)) {
                        headerOffsets ~= offset;
                    }
                }
            }
        }
    }

    void findSemanticParents(Cursor c){
        import std.path: isAbsolute;
        if(!isAbsolute(c.semanticParent.spelling)){
            semanticParentList ~= c.semanticParent;

            findSemanticParents(c.semanticParent);
        }
    }

    void saveMutationInformation(Cursor c) {
        if (!generated && c.extent.path.length != 0 && mutationInInterval(c)
                && isSameBaseName(mutation.path, c.extent.path)) {

            findSemanticParents(c);
            getFunctionDecl(c);

            generated = true;
        }
    }

    @trusted void getFunctionDecl(Cursor c) {
        import clang.c.Index;

        function_name = c.spelling;
        import std.stdio;
        isFunctionVoid = (c.FunctionCursor.resultType.spelling == "void");
        foreach (child; c.children) {
            if (child.kind == CXCursorKind.parmDecl) {
                string tmp = "";
                if (child.tokens[1].spelling == "*") {
                    tmp = child.tokens[0].spelling ~ "*";
                } else {
                    tmp = child.tokens[0].spelling;
                }
                function_params = function_params ~ tmp;
            }
        }
    }
}
