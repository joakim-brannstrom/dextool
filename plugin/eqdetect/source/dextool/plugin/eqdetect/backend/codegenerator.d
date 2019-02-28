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

import dextool.plugin.eqdetect.backend.type : Mutation, EntryFunction, NAME_PREFIX, Parameter;
import dextool.plugin.eqdetect.backend.visitor : TUVisitor;
import dextool.type : FileName;
import std.typecons : Tuple;
import dsrcgen.c : CModule;
import clang.c.Index : CXCursorKind;
import std.algorithm: canFind;
import std.string : strip;

import std.stdio : writeln;

@safe:

import clang.Cursor;
import std.format : format;

int returnIndex;

struct Symbolic{
    string type;
    int index;
}

Parameter[] parmVars;

int varIndex = 0;
Symbolic[] symbolicVariables;

string generateSource(Cursor cursor, Mutation mutation) {
    import std.stdio : File;
    import std.file : getSize;

    auto file = File(cursor.extent.path, "r");
    auto buffer = file.rawRead(new char[getSize(cursor.extent.path)]);

    import std.utf : validate, toUTF8;

    validate(buffer);

    return toUTF8(buffer);
}

auto generateMut(string content, Mutation mutation) {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;
    import dextool.plugin.mutate.backend.type : Offset,
        mutationStruct = Mutation;

    auto mut = makeMutation(cast(mutationStruct.Kind) mutation.kind, mutation.lang);
    auto temp = mut.top() ~ content[0 .. mutation.offset.begin];
    temp = temp ~ mut.mutate(content[mutation.offset.begin .. mutation.offset.end]);
    temp = temp ~ content[mutation.offset.end .. content.length];
    return temp;
}

@trusted auto generateKlee(TUVisitor visitor, FileName source_name, FileName mutant_name) {
    import std.algorithm : canFind;

    auto code = new CModule();
    generateIncludes(code, source_name, mutant_name);
    with (code.func_body(`int`, `main`)) {
        generateVariables(_(), visitor);
        generateSymbolics(_());
        generateAssumes(_());
        if(canFind(visitor.structFields.keys, visitor.entryFunction.returnType.spelling) || visitor.entryFunction.returnType.spelling == "void"){
            generateFuncCall(_(), visitor, visitor.entryFunction.returnType.spelling );
        }
        generateIf(_(), visitor);
        with (else_) {
            stmt(`klee_assert(0)`);
            return_(`0`);
        }
    }
    varIndex = 0;
    symbolicVariables = [];
    parmVars = [];
    return code.render;

}

void generateVariables(CModule code, TUVisitor visitor){
    import std.algorithm : canFind;
    import std.conv;
    import std.stdio;
    Parameter[] params = visitor.entryFunction.function_params;
    int length = to!int(params.length);
    for (int i = 0; i < length; i++) {
        newGenerateVariable(code, visitor, params[i]);
        varIndex++;
    }
}

@trusted void newGenerateVariable(CModule code, TUVisitor visitor, Parameter param){
    import std.algorithm : canFind;

    bool isNameChanged = canFind(visitor.types, param.type.strip("*"));
    bool isPointer = (canFind(param.type, "*") && !canFind(param.type, "char"));
    bool isStruct = canFind(visitor.structFields.keys, param.type.strip("*"));
    generateVariable(code, param, varIndex, isNameChanged);
    parmVars ~= Parameter("", param.type, format(`var%s`, varIndex));
    if(!(isPointer||isStruct)){
        symbolicVariables ~= Symbolic(param.type, varIndex);
        varIndex++;
    }

    if(isStruct){
        int structIndex = varIndex;
        foreach (field; visitor.structFields[param.type.strip("*")]){
            varIndex++; //Struct generates one variable extra for each field
            generateVariable(code, field, varIndex, false);
            generateSymbolic(code, Symbolic(field.type, varIndex));
            generateAssume(code, varIndex);
            code.stmt(format(`var%s.%s = var%s;`, structIndex, field.name, varIndex));
            code.stmt(format(`%svar%s.%s%s = %svar%s;`, NAME_PREFIX, structIndex, isNameChanged ? NAME_PREFIX : "", field.name, NAME_PREFIX, varIndex));
        }
    }
    else if (isPointer){
        varIndex++; //Pointer generates two variables
        newGenerateVariable(code, visitor, Parameter(param.semanticIdentifier, param.type.strip("*"), param.name));
        code.stmt(format(`var%s = &var%s;`, varIndex-1, varIndex));
        code.stmt(format(`%svar%s = &%svar%s;`, NAME_PREFIX, varIndex-1, NAME_PREFIX, varIndex));
        symbolicVariables ~= Symbolic(param.type.strip("*"), varIndex);
    }
}

void generateFieldsCheck(CModule code, TUVisitor visitor, int i, bool isNameChanged){
    foreach (field; visitor.structFields[visitor.entryFunction.function_params[i].type]){
        newGenerateVariable(code, visitor, field);
    }
}
//call voidFunctions between if-statement and assumes
void generateFuncCall(CModule code, TUVisitor visitor, string returnType){
    string paramString = parmVarsAsString(false);
    string mutParamString = parmVarsAsString(true);
    bool isNameChanged = canFind(visitor.types, returnType);
    string notVoid = (returnType != "void") ? format(`%s var%s = `, returnType, varIndex) : "";
    string mutNotVoid = (returnType != "void") ? format(`%s%s %svar%s = `, isNameChanged ? NAME_PREFIX : "", returnType, NAME_PREFIX, varIndex) : "";
    returnIndex = varIndex;
    code.stmt(format(`%s%s%s(%s)`, notVoid, visitor.entryFunction.semanticIdentifier, visitor.entryFunction.function_name, paramString));
    code.stmt(format(`%s%s%s%s(%s)`, mutNotVoid, visitor.entryFunction.semanticIdentifier, NAME_PREFIX, visitor.entryFunction.function_name, mutParamString));
}

@trusted void generateIf(CModule code, TUVisitor visitor){
    import std.algorithm : canFind;
    string paramString = parmVarsAsString(false);
    string mutParamString = parmVarsAsString(true);
    string ifString;

    if(canFind(visitor.structFields.keys, visitor.entryFunction.returnType.spelling)){
        import std.array : split;
        string structName = visitor.entryFunction.returnType.spelling.split("::").length != 1 ? visitor.entryFunction.returnType.spelling.split("::")[$-1] : visitor.entryFunction.returnType.spelling;
        ifString = generateStructCheckString(visitor, Parameter("", structName, format(`var%s`, returnIndex)));
    } else if (visitor.entryFunction.returnType.spelling  != "void"){
        import std.array : replace;
        ifString = format(`%s%s(%s)`, visitor.entryFunction.semanticIdentifier.replace(NAME_PREFIX, ""), visitor.entryFunction.function_name, paramString) ~ "==" ~
        format(`%s%s%s(%s)`, visitor.entryFunction.semanticIdentifier, NAME_PREFIX, visitor.entryFunction.function_name, mutParamString) ~ " && ";
    } else {

    }
    ifString ~= generateReferenceCheckString(visitor);
    if(ifString != ""){
        ifString = ifString[0 .. $-3];
    }
    with(code.if_(ifString)){
        return_(`1`);
    }
}
@trusted string generateReferenceCheckString(TUVisitor visitor){
    string parmString;
    foreach(variable; parmVars){
        if(canFind(visitor.structFields.keys, variable.type.strip("*"))){
            parmString ~= generateStructCheckString(visitor, variable);
        }
        else{
            parmString ~=  format(`%s%s == %s`, NAME_PREFIX, variable.name, variable.name) ~  " && ";
        }
    }
    return parmString;
}
string generateStructCheckString(TUVisitor visitor, Parameter structName){
    string structCheckString = "";
    bool isNameChanged = canFind(visitor.types, structName.type.strip("*"));

    foreach (field; visitor.structFields[structName.type.strip("*")]){
        structCheckString ~= format(`%s.%s == %s%s.%s%s`, structName.name, field.name, NAME_PREFIX, structName.name, isNameChanged ? NAME_PREFIX : "", field.name) ~ " && ";
    }
    return structCheckString;
}

string parmVarsAsString(bool nameprefix){
    string parmString;
    string prefix = nameprefix ? NAME_PREFIX : "";
    foreach(variable; parmVars){
        parmString ~= prefix ~ variable.name ~  ",";
    }
    if(parmString != ""){
        parmString = parmString[0 .. $-1];
    }
    return parmString;
}

void generateVariable(CModule code, Parameter param, int index, bool isLocalToFile){
    string tmp = isLocalToFile ? NAME_PREFIX : "";
    code.stmt(format(`%s%s var%s;`, param.semanticIdentifier, param.type, index));
    code.stmt(format(`%s%s%s %svar%s;`, param.semanticIdentifier, tmp, param.type, NAME_PREFIX, index));
}

void generateSymbolics(CModule code){
    foreach(variable; symbolicVariables){
        generateSymbolic(code, variable);
    }
}

void generateSymbolic(CModule code, Symbolic s){
    code.stmt(format(`klee_make_symbolic(&var%s, sizeof(%s), "var%s")`, s.index, s.type, s.index));
    code.stmt(format(`klee_make_symbolic(&%svar%s, sizeof(%s), "%svar%s")`, NAME_PREFIX, s.index, s.type, NAME_PREFIX, s.index));
}

void generateAssumes(CModule code){
    foreach(variable; symbolicVariables){
        generateAssume(code, variable.index);
    }
}

void generateAssume(CModule code, int index){
    code.stmt(format(`klee_assume(var%s == %svar%s)`, index, NAME_PREFIX, index));
}

void generateIncludes(ref CModule code, FileName source_name, FileName mutant_name){
    // add klee imports
    code.include(`<klee/klee.h>`);
    code.include(`<assert.h>`);

    // add import for the files that are being tested
    code.include(source_name);
    code.include(mutant_name);
}
