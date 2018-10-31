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

void handleMutation(TUVisitor visitor, Mutation mutation) {
    // create file for sourcecode, the mutant and code prepared for KLEE
    mutationEnhancer(visitor, mutation);
    createSourceFiles(visitor, mutation);
    // start the symbolic execution in KLEE
    runKLEE();
    // parse the result
    ErrorResult errorResult = parseKLEE();
    // mark the mutation in the database according to KLEE output
    markMutation(errorResult, mutation);
}

Offset updateMutationOffset(TUVisitor visitor, Offset offset, int i){
    if (offset.begin > visitor.offsets[i].begin
            && offset.end > visitor.offsets[i].end) {
        offset.begin += 2;
        offset.end += 2;
    } else if (offset.begin <= visitor.offsets[i].begin
            && offset.end >= visitor.offsets[i].end) {
        offset.end += 2;
    }
    return offset;
}

void mutationEnhancer(TUVisitor visitor, Mutation mutation) {
    import std.algorithm;
    import std.stdio;
    visitor.offsets.sort!("a.begin > b.begin");
    string text = visitor.generatedSource.render;
    for (int i = 0; i < visitor.offsets.length; i++) {
        text = nameReplacer(text, visitor.offsets[i]);
        mutation.offset = updateMutationOffset(visitor, mutation.offset, i);
    }

    import dextool.plugin.eqdetect.backend.codegenerator : SnippetFinder;

    visitor.generatedMutation.text(SnippetFinder.generateMut(text, mutation));
}

import std.typecons : Tuple;

string nameReplacer(string text, Offset offset) {
    text = text[0 .. offset.begin] ~ "m_" ~ text[offset.begin .. $];
    return text;
}

void createSourceFiles(TUVisitor visitor, Mutation mutation) {
    import std.path : baseName;
    import dextool.plugin.eqdetect.backend : writeToFile, SnippetFinder;
    import dextool.type : FileName;

    FileName source_path = writeToFile(visitor.generatedSource.render,
            baseName(mutation.path), mutation.kind, mutation.id, "_source_");
    FileName mutant_path = writeToFile(visitor.generatedMutation.render,
            baseName(mutation.path), mutation.kind, mutation.id, "_mutant_");
    auto s = SnippetFinder.generateKlee(visitor.function_params, source_path,
            mutant_path, visitor.function_name);
    writeToFile(s, baseName(mutation.path), mutation.kind, mutation.id, "_klee_");
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
