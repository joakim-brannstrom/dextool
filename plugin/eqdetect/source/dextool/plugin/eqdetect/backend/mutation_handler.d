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
import dextool.plugin.eqdetect.backend.type : Mutation, ErrorResult, NAME_PREFIX;
import logger = std.experimental.logger;
import dextool.plugin.mutate.backend.type : Offset;

const string SOURCE_TYPE = "_source_";
const string MUTANT_TYPE = "_mutant_";
const string KLEE_TYPE = "_klee_";

string muttext;
string sourcetext;

// temp variables
//string mutationName;

void handleMutation(TUVisitor visitor, Mutation mutation, const string[] cflags) {
    // change names in the mutantfile
    mutationEnhancer(visitor, mutation);
    // create file for sourcecode, the mutant and code prepared for KLEE
    createSourceFiles(visitor);
    // start the symbolic execution in KLEE
    runKLEE(cflags);
    // parse the result
    ErrorResult errorResult = parseKLEE();
    // mark the mutation in the database according to KLEE output
    markMutation(errorResult, mutation);
}

Offset updateMutationOffset(Offset visitorOffset, Offset offset, int diff){
    if (offset.begin > visitorOffset.begin
            && offset.end > visitorOffset.end) {
        offset.begin += diff;
        offset.end += diff;
    } else if (offset.begin <= visitorOffset.begin
            && offset.end >= visitorOffset.end) {
        offset.end += diff;
    }
    return offset;
}

void mutationEnhancer(TUVisitor visitor, Mutation mutation) {
    import std.algorithm;
    import std.stdio;
    import std.path : stripExtension, extension;
    import std.conv : to;

    visitor.offsets.sort!("a.begin > b.begin");
    visitor.headerOffsets.sort!("a.begin > b.begin");

    FileName source_path = createFilename(visitor, SOURCE_TYPE, ".hpp");

    string text = visitor.generatedSource.render;

    if(visitor.includeOffset.begin != -1){
        //writeln(text);
        int headerDiff = to!int(("\"" ~ source_path ~ "\"").length) - (visitor.includeOffset.end - visitor.includeOffset.begin);
        text = visitor.generatedSource.render[0 .. visitor.includeOffset.begin] ~ "\"" ~
        stripExtension(source_path)~".hpp" ~ "\"" ~ visitor.generatedSource.render[visitor.includeOffset.end .. $];

        for (int i = 0; i < visitor.offsets.length; i++) {
            visitor.offsets[i] = updateMutationOffset(visitor.includeOffset, visitor.offsets[i], headerDiff);
        }
        mutation.offset = updateMutationOffset(visitor.includeOffset, mutation.offset, headerDiff);

    }
    sourcetext = text;

    string text2 = visitor.generatedSourceHeader.render;
    for (int i = 0; i < visitor.offsets.length; i++) {
        text = nameReplacer(text, visitor.offsets[i]);
        mutation.offset = updateMutationOffset(visitor.offsets[i], mutation.offset, NAME_PREFIX.length);
    }
    for (int i = 0; i < visitor.headerOffsets.length; i++) {
        text2 = nameReplacer(text2, visitor.headerOffsets[i]);
    }

    import dextool.plugin.eqdetect.backend.codegenerator;

    visitor.generatedMutation.text(generateMut(text, mutation));
    muttext = visitor.generatedMutation.render;
    visitor.generatedMutationHeader.text(text2);
}

string nameReplacer(string text, Offset offset) {
    import std.stdio;
    //writeln(offset.begin);
    //writeln(text.length);
    text = text[0 .. offset.begin] ~ NAME_PREFIX ~ text[offset.begin .. $];
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
    import dextool.plugin.eqdetect.backend : generateKlee, writeToFile;
    import dextool.type : FileName;

    FileName source_path = createFilename(visitor, SOURCE_TYPE, extension(visitor.mutation.path));
    FileName mutant_path = createFilename(visitor, MUTANT_TYPE, extension(visitor.mutation.path));

    import std.array : replace;
    import std.conv : to;
    muttext = muttext.replace(to!string(stripExtension(source_path)), to!string(stripExtension(mutant_path)));

    writeToFile(sourcetext, source_path);
    writeToFile(muttext, mutant_path);
    //mutationName = mutant_path;
    //writeToFile(sourcetext, FileName("source.cpp"));
    //writeToFile(muttext, FileName("mutant.cpp"));

    auto s = generateKlee(visitor, source_path, mutant_path);
    import std.stdio;
    writeToFile(s, createFilename(visitor, KLEE_TYPE, extension(visitor.mutation.path)));

    string headerExtension = extension(visitor.mutation.path).replace("c", "h");

    source_path = createFilename(visitor, SOURCE_TYPE, headerExtension);
    mutant_path = createFilename(visitor, MUTANT_TYPE, headerExtension);

    //Can't find #ifndef when analyzing the AST, working for now
    muttext = (visitor.generatedMutationHeader.render).replace("#ifndef ", "#ifndef " ~ NAME_PREFIX);

    writeToFile(visitor.generatedSourceHeader.render, source_path);
    writeToFile(muttext, mutant_path);
}

void runKLEE(const string[] cflags) {
    import std.process : executeShell;
    import std.file : getcwd;
    import std.format : format;

    logger.info("KLEE execution started");

    import std.string;
    string incPath = cflags[2].strip("-I");
    logger.info(executeShell("./klee.sh " ~ incPath).output);

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
