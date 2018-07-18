/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

TODO:
- Description of file
*/

module dextool.plugin.eqdetect.backend.mutation_handler;

import dextool.plugin.eqdetect.backend.visitor : TUVisitor;
import dextool.plugin.eqdetect.backend.type : Mutation;
import logger = std.experimental.logger;
import dextool.plugin.eqdetect.backend.type : ErrorResult;

void handleMutation(TUVisitor visitor, Mutation mutation){
    // create file for sourcecode, the mutant and code prepared for KLEE
    createSourceFiles(visitor, mutation);
    // start the symbolic execution in KLEE
    runKLEE();
    // parse the result
    ErrorResult errorResult = parseKLEE();
    // mark the mutation in the database according to KLEE output
    markMutation(errorResult, mutation);
}

void createSourceFiles(TUVisitor visitor, Mutation mutation){
    import std.path : baseName;
    import dextool.plugin.eqdetect.backend : writeToFile, SnippetFinder;
    import dextool.type : FileName;

    FileName source_path = writeToFile(visitor.generatedSource.render,
            baseName(mutation.path), mutation.kind, mutation.id, "_source_");
    FileName mutant_path = writeToFile(visitor.generatedMutation.render,
            baseName(mutation.path), mutation.kind, mutation.id, "_mutant_");
    auto s = SnippetFinder.generateKlee(visitor.function_params,
            source_path, mutant_path, visitor.function_name);
    writeToFile(s, baseName(mutation.path), mutation.kind, mutation.id, "_klee_");
}

void runKLEE(){
    import std.process : executeShell;
    import std.file : getcwd;
    import std.format : format;

    // Spawn a shell and create the klee-container with a mounted volume (current build directory)
    // The created container will execute the klee.sh script and after execution get removed
    logger.info("KLEE execution started");
    auto klee_exec_out = executeShell(format(
            "docker run --rm -it --name=klee_container4 -v %s:/home/klee/mounted klee/klee mounted/klee.sh",
            getcwd())).output;
    logger.info(klee_exec_out);

    // cleanup the temporary directory created
    executeShell("rm -rf eqdetect_generated_files/*");
}

ErrorResult parseKLEE(){
    // parse the result from KLEE execution
    import dextool.plugin.eqdetect.backend.parser : errorTextParser;
    ErrorResult errorResult = errorTextParser("result.txt");

    // remove the result-file
    import std.file : remove;
    remove("result.txt");

    return errorResult;
}

void markMutation(ErrorResult errorResult, Mutation mutation){
    import dextool.plugin.mutate.backend.type : mutationStruct = Mutation;
    import dextool.plugin.eqdetect.backend.dbhandler : setEquivalence;

    switch (errorResult.status) {
    case "Eq":
        setEquivalence(mutation.id, mutationStruct.eq.equivalent);
        break;
    case "Halt":
        setEquivalence(mutation.id, mutationStruct.eq.timeout);
        break;
    default:
        setEquivalence(mutation.id, mutationStruct.eq.not_equivalent);
        break;
    }
}
