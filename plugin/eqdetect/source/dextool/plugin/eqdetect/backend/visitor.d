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

*/

module dextool.plugin.eqdetect.backend.visitor;

import clang.Cursor;
import cpptooling.analyzer.clang.ast : Visitor;
import dextool.plugin.mutate.backend.type : Offset;
import std.stdio;
import clang.c.Index;

@safe:

final class TUVisitor : Visitor {
    import dextool.plugin.eqdetect.backend : Mutation, EntryFunction, Parameter, NAME_PREFIX;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.c : CModule;
    import cpptooling.analyzer.clang.include_visitor;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;
    CModule generatedSource;
    CModule generatedMutation;
    CModule generatedSourceHeader;
    CModule generatedMutationHeader;

    bool generated = false;

    EntryFunction entryFunction;

    string[] types;
    Parameter[][string] structFields;

    string headerPath;

    Offset includeOffset;
    Offset[] offsets;
    Offset[] headerOffsets;



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

    @trusted override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        import std.path : extension;
        import dextool.plugin.eqdetect.backend;
        if(extension(v.cursor.extent.path) == ".cpp" || extension(v.cursor.extent.path) == ".cc"){
            auto s = generateSource(v.cursor, this.mutation);
            generatedSource.text(s);
        }
        else if(extension(v.cursor.extent.path) == ".hpp" || extension(v.cursor.extent.path) == ".h"){
            auto s = generateSource(v.cursor, this.mutation);
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

    override void visit(const(EnumDecl) v) {
        mixin(mixinNodeLog!());
        saveTypes(v.cursor);
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
        if(isSameBaseName(v.cursor.definition.extent.path, mutation.path)){
            checkTypes(v.cursor);
        }

        saveMutationInformation(v.cursor);
        import std.path : extension;
        if(isSameBaseName(v.cursor.extent.path, mutation.path) && extension(v.cursor.extent.path) == ".hpp"){
            headerPath = v.cursor.extent.path;
        }
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

    @trusted Parameter createParameter(Cursor c){
        string lastIdentifier, typeIdentifier, semanticIdentifier;
        string[] semanticIdentifierList;
        bool isPointer = false;
        int length = 0;
        Parameter param;

        foreach(token; c.tokens){
            if (token.kind == CXTokenKind.comment) {continue;}
            if (token.spelling == "*"){
                isPointer = true;
                continue;
            }
            if(token.spelling == "&"){
                continue;
            }
            //semanticIdentifierList ~= token.spelling;

            if (token.kind == CXTokenKind.keyword){
                semanticIdentifierList ~= token.spelling ~ " ";
                typeIdentifier = token.spelling;
            } else if (token.kind == CXTokenKind.identifier) {
                semanticIdentifierList ~= token.spelling;
                if (lastIdentifier != "") {
                    typeIdentifier = lastIdentifier;
                }
                lastIdentifier = token.spelling;
            } else{
                semanticIdentifierList ~= token.spelling;
            }
            length++;
        }
        for (int i = 0; i < length - 2; i++) {
            semanticIdentifier ~= semanticIdentifierList[i];
        }
        param.semanticIdentifier = semanticIdentifier;
        param.type = typeIdentifier;
        if (isPointer) {param.type ~= "*";}
        param.name = lastIdentifier;
        return param;
    }

    @trusted override void visit(const(StructDecl) v) {
        import std.algorithm : canFind;

        mixin(mixinNodeLog!());

        if(!structFields.keys.canFind(v.cursor.spelling)){
            foreach(child ; v.cursor.children){
                if(child.kind == CXCursorKind.fieldDecl){
                    structFields[v.cursor.spelling] ~= createParameter(child);
                }
            }
            saveTypes(v.cursor);
        }
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
        import std.stdio;
        if(isSameBaseName(v.cursor.extent.path, mutation.path)){
            saveOffsets(v.cursor);
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
        import std.algorithm: canFind;
        if(isSameBaseName(c.extent.path, mutation.path)){
            if(!types.canFind(c.spelling)){
                types ~= c.spelling;
            }
        }
    }

    @trusted void checkTypes(Cursor c){
        foreach(t;c.tokens){
            import std.algorithm: canFind;

            if (types.canFind(t.spelling)) {
                checkOffsets(c, t.spelling);
            }
        }
        checkOffsets(c);
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

    bool isDefined(Cursor c){
        return isSameBaseName(c.extent.path, c.definition.extent.path);
    }

    void checkOffsets(Cursor c, string name = ""){
        if(isSameBaseName(c.extent.path, mutation.path) && isDefined(c)){
            saveOffsets(c, name);
        }
    }

    void saveOffsets(Cursor c, string name = "") {
        import std.path: extension;

        if (name == ""){name = c.spelling;}

        Offset offset = findOffset(c, name);

        if(offset.begin != -1 && offset.end != -1){
            import std.algorithm: canFind;
            import std.path : extension;
            import clang.c.Index;

            if(c.kind == CXCursorKind.inclusionDirective){
                includeOffset = offset;
            }
            else if(extension(c.extent.path) == ".cpp" || extension(c.extent.path) == ".cc"){
                if (!offsets.canFind(offset)) {
                    offsets ~= offset;
                }
            }
            else if(extension(c.extent.path) == ".hpp" || extension(c.extent.path) == ".h"){
                if (!headerOffsets.canFind(offset)) {
                    headerOffsets ~= offset;
                }
            }
        }
    }

    @trusted void findSemanticParents(Cursor c){
        import std.path: isAbsolute;
        import std.algorithm : canFind;
        string identifier = "";

        if(!isAbsolute(c.semanticParent.spelling)){
            if (canFind(types, c.semanticParent.spelling)) {
                entryFunction.semanticIdentifier = NAME_PREFIX ~ c.semanticParent.spelling ~ "::" ~ entryFunction.semanticIdentifier;
            } else {
                entryFunction.semanticIdentifier = c.semanticParent.spelling ~ "::" ~ entryFunction.semanticIdentifier;
            }
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
        Parameter param;
        import clang.c.Index;
        entryFunction.function_name = c.spelling;
        entryFunction.returnType = c.FunctionCursor.resultType;
        foreach (child; c.children) {
            if (child.kind == CXCursorKind.parmDecl) {
                entryFunction.function_params ~= createParameter(child);
            }
        }
    }
}
