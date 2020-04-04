/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
//
// This test the preamble for mutants that it works as expected

#include <assert.h>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdlib.h>
#include <string>

#define start_test()                                                                               \
    do {                                                                                           \
        std::cout << " # " << __func__ << "\t\t" << __FILE__ << ":" << __LINE__ << std::endl;      \
    } while (0)
#define msg(x...)                                                                                  \
    do {                                                                                           \
        std::cout << __FILE__ << ":" << __LINE__ << " " << x << std::endl;                         \
    } while (0)

#include "schemata_header.c"

const char* EnvKey = "DEXTOOL_MUTID";

void set_env_mutid(uint64_t v) {
    auto ss = std::string(EnvKey) + "=" + std::to_string(v);
    char* s = new char[ss.length() + 1];
    strcpy(s, ss.c_str());
    assert(putenv(s) == 0);
}

void test_id_read() {
    start_test();

    msg("Setting env to " << 42);
    set_env_mutid(42);

    msg("Let init_dextool_mutid read from env");
    init_dextool_mutid();

    msg("global variable gDEXTOOL_MUTID is " << gDEXTOOL_MUTID);
    assert(gDEXTOOL_MUTID == 42);
}

void test_read_largest() {
    start_test();

    msg("Setting the env to the largest possible value");
    set_env_mutid(UINT64_MAX);

    init_dextool_mutid();

    msg("global variable gDEXTOOL_MUTID is " << gDEXTOOL_MUTID);
    assert(gDEXTOOL_MUTID == UINT64_MAX);
}

int main(int argc, char** argv) {
    assert(getenv(EnvKey) == nullptr);

    test_id_read();
    test_read_largest();
    return 0;
}
