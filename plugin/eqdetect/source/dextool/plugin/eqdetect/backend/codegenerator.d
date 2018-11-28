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
*/

module dextool.plugin.eqdetect.backend.codegenerator;

import dextool.plugin.eqdetect.backend.type : Mutation, EntryFunction, NAME_PREFIX;
import dextool.type : FileName;
import std.typecons : Tuple;
import dsrcgen.c : CModule;
import clang.c.Index : CXCursorKind;
import std.algorithm: canFind;
import std.string : strip;

@safe:

import clang.Cursor;
import std.format : format;

struct EntryPoint {
    string namespace;
    string mutationNamespace;
    string object;
    string mutationObject;
}//TODO:ta bort klass

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
static auto generateKlee(EntryFunction entryFunction, FileName source_name, FileName mutant_name) {

    auto code = new CModule();
    import std.stdio;
    includeGenerator(code, source_name, mutant_name);
    // add klee-main
    mainGenerator(code, entryFunction);
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
    ref EntryPoint entryPoint){

    import std.conv : to;

    for (int i = to!int(semanticParentList.length)-1; i >= 1; i--){
        if (semanticParentList[i].kind == CXCursorKind.namespace){
            entryPoint.namespace ~= semanticParentList[i].spelling ~ "::";
            entryPoint.mutationNamespace ~= semanticParentList[i].spelling ~ "::";
        } else {
            entryPoint.namespace ~= semanticParentList[i].spelling ~ "::";
            entryPoint.mutationNamespace ~= NAME_PREFIX ~ semanticParentList[i].spelling ~ "::";
        }
    }
}

static void generateVariables(CModule code, string[] params, ref string func_params){
    // variable declaration
    for (int i = 0; i < params.length; i++) {
        code.stmt(format(`%s var%s;`, params[i], i));
        func_params = func_params ~ format(`var%s,`, i);
        if(params[i].canFind('*')){
            code.stmt(format(`%s var%s;`, strip(params[i],"*"), i+params.length));
            code.stmt(format(`var%s = &var%s;`, i, i+params.length));
        }
    }

    // remove last comma that was inserted into the parameters
    if (func_params.length != 0) {
        func_params = func_params[0 .. $ - 1];
    }

    // symbolic variable for each parameter
    import std.stdio;


    for (int i = 0; i < params.length; i++) {
        if(params[i].canFind('*')){
            code.stmt(format(`klee_make_symbolic(&var%s, sizeof(%s), "var%s")`, i+params.length, strip(params[i],"*"), i+params.length));
        }
        else{
            code.stmt(format(`klee_make_symbolic(&var%s, sizeof(%s), "var%s")`, i, params[i], i));
        }
    }
}

static void generateNamespacesAndObjects(CModule code, ref EntryPoint entryPoint, Cursor[] semanticParentList){
    nameSpaceStringGenerator(semanticParentList, entryPoint);
    import std.stdio;
    if(semanticParentList.length != 0){
        if (semanticParentList[0].kind == CXCursorKind.namespace){
            entryPoint.namespace ~= semanticParentList[0].spelling ~ "::";
        } else if (semanticParentList[0].kind == CXCursorKind.classDecl ||
        semanticParentList[0].kind == CXCursorKind.structDecl) {
            code.stmt(format(`%s%s kleeObject`, entryPoint.namespace, semanticParentList[0].spelling));
            code.stmt(format(`%s%s%s %skleeObject`, entryPoint.mutationNamespace, NAME_PREFIX, semanticParentList[0].spelling, NAME_PREFIX));
            entryPoint.namespace = ".";
            entryPoint.mutationNamespace = ".";
            entryPoint.object = "kleeObject";
            entryPoint.mutationObject = NAME_PREFIX ~ "kleeObject";
        }
    }
}

static void generateEquivalenceCheck(CModule code, EntryFunction entryFunction, EntryPoint entryPoint, string func_params){
        if(entryFunction.isFunctionVoid){
            //Only intended for pure void-functions
            string mut_params;
            for (int i = 0; i < entryFunction.function_params.length; i++) {
                code.stmt(format(`%s %svar%s;`, entryFunction.function_params[i], NAME_PREFIX, i));
                mut_params = mut_params ~ format(`%svar%s,`, NAME_PREFIX, i);
                if(entryFunction.function_params[i].canFind('*')){
                    code.stmt(format(`%s %svar%s;`, strip(entryFunction.function_params[i],"*"), NAME_PREFIX, i+entryFunction.function_params.length));
                    code.stmt(format(`%svar%s = &%svar%s;`, NAME_PREFIX, i, NAME_PREFIX, i+entryFunction.function_params.length));
                }
            }
            if (mut_params.length != 0) {
                mut_params = mut_params[0 .. $ - 1];
            }

            // symbolic variable for each parameter
            string ifstring;
            for (int i = 0; i < entryFunction.function_params.length; i++) {
                if(entryFunction.function_params[i].canFind('*')){
                    code.stmt(format(`klee_make_symbolic(&%svar%s, sizeof(%s), "%svar%s")`, NAME_PREFIX, i+entryFunction.function_params.length, strip(entryFunction.function_params[i],"*"), NAME_PREFIX, i+entryFunction.function_params.length));
                    ifstring ~= format(`*var%s == *%svar%s`, i, NAME_PREFIX, i);
                }
                else{
                    code.stmt(format(`klee_make_symbolic(&%svar%s, sizeof(%s), "%svar%s")`, NAME_PREFIX, i, entryFunction.function_params[i], NAME_PREFIX, i));
                    ifstring ~= format(`var%s == %svar%s`, i, NAME_PREFIX, i);
                }

                if(i != entryFunction.function_params.length-1){
                    ifstring ~= " && ";
                }
            }
            with(code.if_(ifstring)){
                code.stmt(format(`%s%s%s(%s)`, entryPoint.object, entryPoint.namespace, entryFunction.function_name, func_params));
                code.stmt(format(`%s%s%s%s(%s)`, entryPoint.mutationObject, entryPoint.mutationNamespace, NAME_PREFIX, entryFunction.function_name, mut_params));
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
            with (code.if_(format(`%s%s%s(%s) == %s%s%s%s(%s)`, entryPoint.object, entryPoint.namespace, entryFunction.function_name, func_params,
                        entryPoint.mutationObject, entryPoint.mutationNamespace, NAME_PREFIX, entryFunction.function_name, func_params))){
                    return_(`0`);
            }
            with (code.else_) {
                stmt(`klee_assert(0)`);
                return_(`0`);
            }
        }
}

static void mainGenerator(ref CModule code, EntryFunction entryFunction){

     string func_params;
     with (code.func_body(`int`, `main`)) {
        generateVariables(_(), entryFunction.function_params, func_params);

        // equivalence detection
        EntryPoint entryPoint;// namespaceString, mutNamespaceString, lastObject, lastMutObject;
        generateNamespacesAndObjects(_(), entryPoint, entryFunction.semanticParentList);

        generateEquivalenceCheck(_(), entryFunction, entryPoint, func_params);

    }
}
