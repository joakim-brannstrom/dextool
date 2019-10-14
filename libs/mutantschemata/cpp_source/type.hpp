/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

C++ types for easier communication between C++ and D code.
*/
#pragma once

#include "cpp_string.hpp"

namespace CppType {

struct SourceLoc {
    uint64_t line;
    uint64_t column;
};
struct Offset {
    uint64_t begin;
    uint64_t end;
};
struct SchemataMutant {
    uint64_t id;
    uint64_t mut_id;
    SourceLoc loc;
    Offset offset;
    uint64_t status;
    CppString::CppStr inject;
    CppString::CppStr filePath;
};

} // namespace CppType
