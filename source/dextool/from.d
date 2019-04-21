/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The license of this module is Boost because the code is derived from a pull
request for druntime.

Local imports everywhere.

Example:
---
std_.foo fun(std_.string.Path p)
---
*/
module dextool.from;

enum from = FromImpl!null();
enum std_ = from.std;

private:

template isModuleImport(string import_) {
    enum isModuleImport = __traits(compiles, { mixin("import ", import_, ";"); });
}

template isSymbolInModule(string module_, string symbol) {
    static if (isModuleImport!module_) {
        enum import_ = module_ ~ ":" ~ symbol;
        enum isSymbolInModule = __traits(compiles, {
                mixin("import ", import_, ";");
            });
    } else {
        enum isSymbolInModule = false;
    }
}

template FailedSymbol(string symbol, string module_) {
    auto FailedSymbol(Args...)(auto ref Args args) {
        static assert(0, "Symbol \"" ~ symbol ~ "\" not found in " ~ module_);
    }
}

struct FromImpl(string module_) {
    template opDispatch(string symbol) {
        static if (isSymbolInModule!(module_, symbol)) {
            mixin("import ", module_, "; alias opDispatch = ", symbol, ";");
        } else {
            static if (module_.length == 0) {
                enum opDispatch = FromImpl!(symbol)();
            } else {
                enum import_ = module_ ~ "." ~ symbol;
                static if (isModuleImport!import_) {
                    enum opDispatch = FromImpl!(import_)();
                } else {
                    alias opDispatch = FailedSymbol!(symbol, module_);
                }
            }
        }
    }
}
