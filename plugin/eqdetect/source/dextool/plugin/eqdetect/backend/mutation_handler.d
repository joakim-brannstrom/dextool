/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file handles the mutation in terms of creating the files which KLEE needs to
perform symbolic execution. It also starts KLEE (in a docker image for now) and parses
the result before marking the mutation in the database.
*/

module dextool.plugin.eqdetect.backend.mutation_handler;

import dextool.plugin.eqdetect.backend.visitor : TUVisitor;
import dextool.plugin.eqdetect.backend.type : Mutation, ErrorResult;
import logger = std.experimental.logger;
import dextool.plugin.mutate.backend.type : Offset;

const string SOURCE_TYPE = "_source_";
const string MUTANT_TYPE = "_mutant_";
const string KLEE_TYPE = "_klee_";

void handleMutation(TUVisitor visitor, Mutation mutation) {
    // create file for sourcecode, the mutant and code prepared for KLEE
    mutationEnhancer(visitor, mutation);
    createSourceFiles(visitor);
    // start the symbolic execution in KLEE
    runKLEE();
    // parse the result
    ErrorResult errorResult = parseKLEE();
    // mark the mutation in the database according to KLEE output
    markMutation(errorResult, mutation);
}

Offset updateMutationOffset(Offset visitorOffset, Offset offset){
    if (offset.begin > visitorOffset.begin
            && offset.end > visitorOffset.end) {
        offset.begin += 2;
        offset.end += 2;
    } else if (offset.begin <= visitorOffset.begin
            && offset.end >= visitorOffset.end) {
        offset.end += 2;
    }
    return offset;
}

void mutationEnhancer(TUVisitor visitor, Mutation mutation) {
    import std.algorithm;
    import std.stdio;
    visitor.offsets.sort!("a.begin > b.begin");
    visitor.headerOffsets.sort!("a.begin > b.begin");
    string text = visitor.generatedSource.render;
    string text2 = visitor.generatedSourceHeader.render;
    for (int i = 0; i < visitor.offsets.length; i++) {
        text = nameReplacer(text, visitor.offsets[i]);
        mutation.offset = updateMutationOffset(visitor.offsets[i], mutation.offset);
    }
    for (int i = 0; i < visitor.headerOffsets.length; i++) {
        text2 = nameReplacer(text2, visitor.headerOffsets[i]);
    }

    import dextool.plugin.eqdetect.backend.codegenerator : SnippetFinder;

    visitor.generatedMutation.text(SnippetFinder.generateMut(text, mutation));
    visitor.generatedMutationHeader.text(text2);
}

string nameReplacer(string text, Offset offset) {
    text = text[0 .. offset.begin] ~ "m_" ~ text[offset.begin .. $];
    return text;
}

import dextool.type : FileName;

FileName createFilename(TUVisitor visitor, string filetype, string extension){
    import std.path : baseName, stripExtension;
    import std.conv : to;
    import dextool.plugin.mutate.backend.type : mutationStruct = Mutation;

    FileName base = stripExtension(baseName(visitor.mutation.path));
    string kind = to!string(cast(mutationStruct.Kind) visitor.mutation.kind);
    string id = to!string(visitor.mutation.id);
    FileName ret = (base ~ filetype ~ id ~ "_" ~ kind ~ extension);
    return ret;
}

void createSourceFiles(TUVisitor visitor) {
    import std.path : extension, stripExtension;
    import dextool.plugin.eqdetect.backend : writeToFile, SnippetFinder;
    import dextool.type : FileName;

    FileName source_path = createFilename(visitor, SOURCE_TYPE, extension(visitor.mutation.path));
    FileName mutant_path = createFilename(visitor, MUTANT_TYPE, extension(visitor.mutation.path));

    string muttext;
    string sourcetext;

    if (visitor.includeOffset.begin != -1 && visitor.includeOffset.end != -1){
        muttext = visitor.generatedMutation.render[0 .. visitor.includeOffset.begin] ~ "\"" ~
        stripExtension(mutant_path)~".hpp" ~ "\"" ~ visitor.generatedMutation.render[visitor.includeOffset.end .. $];
        sourcetext = visitor.generatedSource.render[0 .. visitor.includeOffset.begin] ~ "\"" ~
        stripExtension(source_path)~".hpp" ~ "\"" ~ visitor.generatedSource.render[visitor.includeOffset.end .. $];
    } else {
        muttext = visitor.generatedMutation.render;
        sourcetext = visitor.generatedSource.render;
    }

    writeToFile(sourcetext, source_path);
    writeToFile(muttext, mutant_path);

    auto s = SnippetFinder.generateKlee(visitor.function_params, source_path,
            mutant_path, visitor.function_name, visitor.semanticParentList, visitor.isFunctionVoid);

    writeToFile(s, createFilename(visitor, KLEE_TYPE, extension(visitor.mutation.path)));

    import std.array : replace;
    string headerExtension = extension(visitor.mutation.path).replace("c", "h");

    source_path = createFilename(visitor, SOURCE_TYPE, headerExtension);
    mutant_path = createFilename(visitor, MUTANT_TYPE, headerExtension);

    //Can't find #ifndef when analyzing the AST, working for now
    muttext = (visitor.generatedMutationHeader.render).replace("#ifndef ", "#ifndef m_");

    writeToFile(visitor.generatedSourceHeader.render, source_path);
    writeToFile(muttext, mutant_path);
}

void runKLEE() {
    import std.process : executeShell;
    import std.file : getcwd;
    import std.format : format;

    logger.info("KLEE execution started");

    //TODO: get rid of klee.sh
    logger.info(executeShell("./klee.sh").output);

    // cleanup the temporary directory created
    executeShell("rm -rf eqdetect_generated_files/*");
}

ErrorResult parseKLEE() {
    // parse the result from KLEE execution
    import dextool.plugin.eqdetect.backend.parser : errorTextParser;

    ErrorResult errorResult = errorTextParser("result.txt");

    // remove the result-file
    import std.file : remove;

    remove("result.txt");

    return errorResult;
}

void markMutation(ErrorResult errorResult, Mutation mutation) {
    import dextool.plugin.mutate.backend.type : mutationStruct = Mutation;
    import dextool.plugin.eqdetect.backend.dbhandler : setEquivalence;

    switch (errorResult.status) {
    case "Eq":
        setEquivalence(mutation.id, mutationStruct.eq.equivalent);
        break;
    case "Halt":
        setEquivalence(mutation.id, mutationStruct.eq.timeout);
        break;
    case "ERROR":
        setEquivalence(mutation.id, mutationStruct.eq.unknown);
        break;
    case "Assert":
        setEquivalence(mutation.id, mutationStruct.eq.not_equivalent);
        break;
    default:
        setEquivalence(mutation.id, mutationStruct.eq.not_equivalent);
        break;
    }
}
