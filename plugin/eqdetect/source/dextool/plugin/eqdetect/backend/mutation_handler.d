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
import dextool.plugin.eqdetect.backend.type : Mutation;
import logger = std.experimental.logger;
import dextool.plugin.eqdetect.backend.type : ErrorResult;

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

void mutationEnhancer(TUVisitor visitor, Mutation mutation) {
    import std.stdio;

    import std.algorithm;

    visitor.offsets.sort!("a[0] > b[0]");
    string text = visitor.generatedSource.render;
    for (int i = 0; i < visitor.offsets.length; i++) {
        text = nameReplacer(text, visitor.offsets[i]);
        if (mutation.offset_begin > visitor.offsets[i][0]
                && mutation.offset_end > visitor.offsets[i][1]) {
            mutation.offset_begin += 2;
            mutation.offset_end += 2;
        } else if (mutation.offset_begin <= visitor.offsets[i][0]
                && mutation.offset_end >= visitor.offsets[i][1]) {
            mutation.offset_end += 2;
        }
    }

    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;
    import dextool.plugin.mutate.backend.type : Offset,
        mutationStruct = Mutation;

    auto mut = makeMutation(cast(mutationStruct.Kind) mutation.kind, mutation.lang);
    auto temp = mut.top() ~ text[0 .. mutation.offset_begin];
    temp = temp ~ mut.mutate(text[mutation.offset_begin .. mutation.offset_end]);
    temp = temp ~ text[mutation.offset_end .. $];
    writeln(temp);
    visitor.generatedMutation.text(temp);
}

import dextool.plugin.mutate.backend.type : Offset;
import std.typecons : Tuple;

string nameReplacer(string text, Tuple!(uint, uint) offset) {
    text = text[0 .. offset[0]] ~ "m_" ~ text[offset[0] .. $];
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
