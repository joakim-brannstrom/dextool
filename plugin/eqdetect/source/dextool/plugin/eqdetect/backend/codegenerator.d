/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the functionality for extracting snippets of code from a given cursor
and returns a validated UTF8 string of the extracted code. It also returns the mutated
version of the code extracted.
TODO: rename SnippetFinder*/

module dextool.plugin.eqdetect.backend.codegenerator;

import dextool.plugin.eqdetect.backend.type : Mutation;
import dextool.type : FileName;
import std.typecons : Tuple;
import dsrcgen.c : CModule;
import clang.c.Index : CXCursorKind;

@safe:

class SnippetFinder {
    import clang.Cursor;
    import std.format : format;

    static string generateSource(Cursor cursor, Mutation mutation) {
        import std.stdio : File;
        import std.file : getSize;

        auto file = File(cursor.extent.path, "r");
        auto buffer = file.rawRead(new char[getSize(cursor.extent.path)]);

        import std.utf : validate, toUTF8;

        validate(buffer);

        return toUTF8(buffer);
    }

    static auto generateMut(string content, Mutation mutation) {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutation;
        import dextool.plugin.mutate.backend.type : Offset,
            mutationStruct = Mutation;

        auto mut = makeMutation(cast(mutationStruct.Kind) mutation.kind, mutation.lang);
        auto temp = mut.top() ~ content[0 .. mutation.offset.begin];
        temp = temp ~ mut.mutate(content[mutation.offset.begin .. mutation.offset.end]);
        temp = temp ~ content[mutation.offset.end .. content.length];
        return temp;
    }

    // Generating code that will be used by klee to evaluate the source and mutant code.
    static auto generateKlee(string[] params, FileName source_name,
            FileName mutant_name, string function_name, Cursor[] semanticParentList, bool isFunctionVoid) {

        auto code = new CModule();
        import std.stdio;
        includeGenerator(code, source_name, mutant_name);
        // add klee-main
        mainGenerator(code, params, function_name, semanticParentList, isFunctionVoid);
        return code.render;
    }

    static void includeGenerator(ref CModule code, FileName source_name, FileName mutant_name){
        // add klee imports
        code.include(`<klee/klee.h>`);
        code.include(`<assert.h>`);

        // add import for the files that are being tested
        code.include(source_name);
        code.include(mutant_name);
    }

    static void nameSpaceStringGenerator(Cursor[] semanticParentList,
        ref string namespaceString, ref string mutNamespaceString){

        import std.conv : to;

        for (int i = to!int(semanticParentList.length)-1; i >= 1; i--){
            if (semanticParentList[i].kind == CXCursorKind.namespace){
                namespaceString ~= semanticParentList[i].spelling ~ "::";
                mutNamespaceString ~= semanticParentList[i].spelling ~ "::";
            } else {
                namespaceString ~= semanticParentList[i].spelling ~ "::";
                mutNamespaceString ~= "m_" ~ semanticParentList[i].spelling ~ "::";
            }
        }
    }

    static void mainGenerator(ref CModule code, string[] params,
     string function_name, Cursor[] semanticParentList, bool isFunctionVoid){

         string func_params;
         with (code.func_body(`int`, `main`)) {

            // variable declaration
            for (int i = 0; i < params.length; i++) {
                stmt(format(`%s var%s;`, params[i], i));
                func_params = func_params ~ format(`var%s,`, i);
            }

            // remove last comma that was inserted into the parameters
            if (func_params.length != 0) {
                func_params = func_params[0 .. $ - 1];
            }

            // symbolic variable for each parameter
            for (int i = 0; i < params.length; i++) {
                stmt(format(`klee_make_symbolic(&var%s, sizeof(%s), "var%s")`, i, params[i], i));
            }

            // equivalence detection
            string namespaceString, mutNamespaceString, lastObject, lastMutObject;

            nameSpaceStringGenerator(semanticParentList, namespaceString, mutNamespaceString);
            import std.stdio;
            if(semanticParentList.length != 0){
                if (semanticParentList[0].kind == CXCursorKind.namespace){
                    namespaceString ~= semanticParentList[0].spelling ~ "::";
                } else if (semanticParentList[0].kind == CXCursorKind.classDecl ||
                semanticParentList[0].kind == CXCursorKind.structDecl) {
                    stmt(format(`%s%s kleeObject`, namespaceString, semanticParentList[0].spelling));
                    stmt(format(`%sm_%s m_kleeObject`, mutNamespaceString, semanticParentList[0].spelling));
                    namespaceString = ".";
                    mutNamespaceString = ".";
                    lastObject = "kleeObject";
                    lastMutObject = "m_kleeObject";
                }
            }

            if(isFunctionVoid){
                //Only intended for pure void-functions
                string mut_params;
                for (int i = 0; i < params.length; i++) {
                    stmt(format(`%s m_var%s;`, params[i], i));
                    mut_params = mut_params ~ format(`m_var%s,`, i);
                }
                if (mut_params.length != 0) {
                    mut_params = mut_params[0 .. $ - 1];
                }

                // symbolic variable for each parameter
                string ifstring;
                for (int i = 0; i < params.length; i++) {
                    stmt(format(`klee_make_symbolic(&m_var%s, sizeof(%s), "m_var%s")`, i, params[i], i));
                    ifstring ~= format(`var%s == m_var%s`, i, i);
                    if(i != params.length-1){
                        ifstring ~= " && ";
                    }
                }
                with(if_(ifstring)){
                    stmt(format(`%s%s%s(%s)`, lastObject, namespaceString, function_name, func_params));
                    stmt(format(`%s%sm_%s(%s)`, lastMutObject, namespaceString, function_name, mut_params));
                    with(if_(ifstring)){
                        return_(`0`);
                    }
                    with (else_) {
                        stmt(`klee_assert(0)`);
                        return_(`0`);
                    }
                }
            }
            else{
                with (if_(format(`%s%s%s(%s) == %s%sm_%s(%s)`, lastObject, namespaceString, function_name, func_params,
                            lastMutObject, mutNamespaceString, function_name, func_params))){
                        return_(`0`);
                }
                with (else_) {
                    stmt(`klee_assert(0)`);
                    return_(`0`);
                }
            }
        }
    }
}
