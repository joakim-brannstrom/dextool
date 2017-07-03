/// @file main.cpp
/// @brief Generated by DEXTOOL_VERSION: v1.1.0-204-gb0fe35e
/// DO NOT EDIT THIS FILE, it will be overwritten on update.
#include "dextool/dextool.hpp"

namespace dextool {

namespace {
dextool::Context* ctx;
dextool::DefaultSource* default_src;
} //NS:

DefaultSource& get_default_source() {
    return *default_src;
}

} // NS: dextool

int main(int argc, char** argv) {
    dextool::ctx = dextool::create_context();
    dextool::default_src = new dextool::DefaultSource(dextool::ctx->guide_data, dextool::ctx->inf_data);

    dextool::get_fuzz_runner().run();

    delete dextool::default_src;
    delete dextool::ctx;

    return 0;
}
