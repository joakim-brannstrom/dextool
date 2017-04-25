module backend.fuzz.types;

import dsrcgen.cpp : CppModule;
import cpptooling.data.representation : CppRoot;

struct nsclass {
    bool isPort;
    CppModule cppm;
    string name;
    string impl_name;
}

enum Kind {
    none,
    ContinousInterface,
}

struct ImplData {
    import cpptooling.data.type : CppMethodName;

    CppRoot root;
    alias root this;

    /// Tagging of nodes in the root
    Kind[size_t] kind;

    static auto make() {
        return ImplData(CppRoot.make);
    }

    @safe void tag(size_t id, Kind kind_) {
        kind[id] = kind_;
    }

    Kind lookup(size_t id) {
        if (auto k = id in kind) {
            return *k;
        }

        return Kind.none;
    }
}

struct AppName {
    string payload;
    alias payload this;
}