#include "test_double.hpp"

#ifdef DEXTOOL_TEST
#include "test_double.hpp"
#endif

int main(int argc, char** argv) {
    return SINGLE_FILE == 1 ? 0 : 1;
}
