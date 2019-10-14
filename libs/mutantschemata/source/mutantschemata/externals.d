/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

All the external items used in the api between C++ and D code
*/
module mutantschemata.externals;

// External C++ interface
extern (C++):
interface SchemataApiCpp {
    void apiInsertSchemataMutant(SchemataMutant);
    SchemataMutant apiSelectSchemataMutant(CppStr);
    void apiBuildMutant();
    void apiDeleteMutant(CppStr);
}

// External C++ functions
void runSchemataCpp(SchemataApiCpp, CppStr, CppStr, CppStr);
int setEnvironmentVariable(CppStr, CppStr);

// External C++ string implementation
extern (C++,CppString):
struct CppStr {
    void* cppStr;

    const(void)* ptr();
    int length();
    void destroy();
    void put(char);
}

CppStr getStr();
CppStr createCppStr();

// External C++ types
extern (C++,CppType):
struct SourceLoc {
    ulong line;
    ulong column;
}

struct Offset {
    ulong begin;
    ulong end;
}

struct SchemataMutant {
    ulong id;
    ulong mut_id;
    SourceLoc loc;
    Offset offset;
    ulong status;
    CppStr inject;
    CppStr filePath;
}

struct SchemataFile {
    CppStr fpath;
    SchemataMutant[] mutants;
    CppStr code;
}
