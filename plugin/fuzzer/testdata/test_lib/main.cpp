/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "dextool/dextool.hpp"
#include "dextool/afl_integration.hpp"

namespace dextool {
namespace  {
dextool::DefaultSource* stdin_src;
} //NS:

DefaultSource& get_default_source() {
    return *stdin_src;
}
} //NS:dextool

int main(int argc, char** argv) {
    return dextool::afl_main(argc, argv, &dextool::stdin_src);
}
