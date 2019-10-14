/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Types created for specific use in the mutantschemata API
*/
module mutantschemata.type;

import core.time : Duration;
import std.typecons : Tuple;

import mutantschemata.externals;
import mutantschemata.d_string : cppToD;

import dextool.compilation_db : CompileCommandDB;
import dextool.type : AbsolutePath, Path, ExitStatusType;

const string MUTANT_NR = "MUTANT_NR";

alias execVal = Tuple!(int, "status", string, "output");

struct SchemataFileString {
    string fpath;
    SchemataMutant[] mutants;
    string code;
}

struct SchemataInformation {
    AbsolutePath databasePath;
    CompileCommandDB compileCommand;
    AbsolutePath compileCommandPath;
    bool isActive;

    this(AbsolutePath db, CompileCommandDB ccdb, AbsolutePath ccdbPath, bool active) @safe {
        this.databasePath = db;
        this.compileCommand = ccdb;
        this.compileCommandPath = ccdbPath;
        this.isActive = active;
    }
}

struct MeasureResult {
    ExitStatusType status;
    Duration runtime;
}

struct DSchemataMutant {
    ulong id;
    ulong mut_id;
    SourceLoc sourceLocation;
    Offset offset;
    ulong status;
    string inject;
    AbsolutePath filePath;

    this(SchemataMutant sm) {
        id = sm.mut_id;
        mut_id = sm.mut_id; // TODO: can we remove?
        sourceLocation = sm.loc;
        offset = sm.offset;
        status = sm.status;
        inject = cppToD!CppStr(sm.inject);
        filePath = AbsolutePath(Path(cppToD!CppStr(sm.filePath)));
    }
}
