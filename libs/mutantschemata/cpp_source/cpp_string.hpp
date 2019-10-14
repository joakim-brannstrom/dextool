/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Headerfile for cpp_string.cpp
String implementation for sending strings back and forth between D and C++
*/
#pragma once

#include <stdint.h>
#include <string.h>
#include <string>
#include <iostream>

const int ONE_CHARACTER = 1;

namespace CppString {

struct CppStr{
    std::string* cppStr;

    const void* ptr();
    int length();
    void destroy();
    void put(char);
};
CppStr getStr(const char*);
CppStr createCppStr();

} // CppString
