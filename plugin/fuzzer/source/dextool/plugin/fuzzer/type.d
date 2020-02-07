/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.type;

public import cpptooling.data.symbol.types : FullyQualifiedNameType;
public import dextool.type : Path;

struct SequenceId {
    bool isValid;
    ulong payload;
    alias payload this;
}

/// Symbol with parameter data.
@safe struct Symbol {
    enum FilterKind {
        keep,
        exclude
    }

    FullyQualifiedNameType fullyQualifiedName;
    Param[] limits;

    FilterKind filter;

    Fuzz fuzz;

    SequenceId sequenceId;

    bool hasFuzz() {
        return fuzz.use.length != 0;
    }

    bool hasInclude() {
        return fuzz.include.length != 0;
    }
}

/// Fuzzer function to use.
struct Fuzz {
    FullyQualifiedNameType use;

    /// File the function exist in.
    Path include;

    /// Parameters used when calling the custom fuzzer
    string param;
}

/// Data for a parameter such as limits.
@safe struct Param {
    static struct Check {
        string payload;
        alias payload this;
    }

    static struct Condition {
        string payload;
        alias payload this;
    }

    static struct Identifier {
        string payload;
        alias payload this;
    }

    Check check;
    Fuzz fuzz;
    Condition condition;
    Identifier identifier;

    bool hasCheck() {
        return check.length != 0 && condition.length != 0;
    }

    bool hasFuzz() {
        return fuzz.use.length != 0;
    }
}
