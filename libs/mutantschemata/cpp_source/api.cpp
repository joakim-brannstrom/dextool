/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

C++ part of the SchemataApi. Meant to be used by the Mutant Schemata C++ library
in order to call D code and insert/select mutants from db obtained from Dextool mutate.
*/
#include "api.hpp"
#include "rewrite.hpp"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <sstream>

void runSchemataCpp(SchemataApiCpp* sac, CppString::CppStr cs, CppString::CppStr ccdbPath,
                    CppString::CppStr restricted) {
    std::string buf;                          // Have a buffer string
    std::stringstream ss(cs.cppStr->c_str()); // Insert the string into a stream
    std::vector<std::string> filesToMutate;   // Create vector to hold our words

    while (getline(ss, buf, ',')) {
        filesToMutate.push_back(buf);
    }

    // Creating the strings we want in our fake argv
    std::vector<std::string> arguments = {"-p", ccdbPath.cppStr->c_str()};
    arguments.insert(arguments.end(), filesToMutate.begin(), filesToMutate.end());

    // Populate the fake argv
    std::vector<const char*> argv;
    for (const auto& arg : arguments) {
        argv.push_back((const char*)arg.data());
    }
    argv.push_back(nullptr);

    // Call setup of clang
    setupClang(argv.size() - 1, argv.data(), sac, restricted);
}
int setEnvironmentVariable(CppString::CppStr variable, CppString::CppStr value) {
    return setenv(variable.cppStr->c_str(), value.cppStr->c_str(), 1);
}
