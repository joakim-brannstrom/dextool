/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains utilities to reduce the boilerplate when implementing a
FSM.

# Callback Builder
Useful to generate the callbacks that control the actions to perform in an FSM
or the state transitions.
*/
module dextool.fsm;

/** Generate a mixin of callbacks for each literal in `EnumT`.
 *
 * Example:
 * ---
 * enum MyAct { foo }
 * mixin(makeCallback!MyAct.switchOn("act").callbackOn("obj").finalize);
 * // generates a callback such as this
 * obj.actFoo();
 * ---
 *
 * Params:
 *  EnumT = enum to switch on. All literals must be implemented as callbacks.
 */
BuildCallbacks!EnumT makeCallbacks(EnumT)() {
    return BuildCallbacks!EnumT();
}

struct BuildCallbacks(EnumT) {
    private {
        /// variable determining the callback.
        string callbackSwitch_;
        /// if specified it will be the object to do the callbacks on.
        string objVar_;
        /// prefi all callbacks with this string.
        string prefix_;
        /// default parameters used in the callback
        string[] defaultParams_;
        /// if accessing EnumT requires lookup specification
        string lookup_;
    }

    /// specific parameters for an enum literal.
    string[][EnumT] specificParams;

    /// How to lookup `EnumT`, if needed.
    auto lookup(string v) {
        this.lookup_ = v;
        return this;
    }

    /// Determine which callback to use.
    auto switchOn(string v) {
        this.callbackSwitch_ = v;
        return this;
    }

    /// Object to do the callbacks on, if specified.
    auto callbackOn(string v) {
        this.objVar_ = v;
        return this;
    }

    /// Prefix all callbacks with `v`.
    auto prefix(string v) {
        this.prefix_ = v;
        return this;
    }

    /// Default parameters to pass on to all callbacks.
    auto defaultParams(string[] v) {
        this.defaultParams_ = v;
        return this;
    }

    /// If a specific callback requires unique parameters.
    auto specificParam(EnumT e, string[] v) {
        this.specificParams[e] = v;
        return this;
    }

    /// Returns: the mixin code doing the callbacks as specified.
    string finalize() {
        import std.conv : to;
        import std.format : format;
        import std.traits : EnumMembers;
        import std.uni : toUpper;

        const enumFqn = () {
            if (lookup_.length == 0)
                return EnumT.stringof;
            return lookup_ ~ "." ~ EnumT.stringof;
        }();
        string s = format("final switch(%s) {\n", callbackSwitch_);
        static foreach (a; EnumMembers!EnumT) {
            {
                const literal = a.to!string;
                const callback = () {
                    if (prefix_.length == 0)
                        return literal;
                    else if (literal.length == 1)
                        return prefix_ ~ literal.toUpper;
                    return format("%s%s%s", prefix_, literal[0].toUpper, literal[1 .. $]);
                }();
                const obj = objVar_ is null ? null : objVar_ ~ ".";
                const paramsRaw = () {
                    if (auto p = a in specificParams)
                        return *p;
                    return defaultParams_;
                }();
                const params = format("%-(%s, %)", paramsRaw);
                s ~= format("case %s.%s: %s%s(%s);break;\n", enumFqn, literal,
                        obj, callback, params);
            }
        }
        s ~= "}";

        return s;
    }
}

@("shall construct a string with callbacks for each enum literal")
unittest {
    static struct Struct {
        enum Dummy {
            a,
            fortyTwo
        }
    }

    void preA(string x) {
    }

    void preFortyTwo(string a, string b) {
    }

    Struct.Dummy sw;
    enum r = makeCallbacks!(Struct.Dummy).lookup("Struct").switchOn("sw")
            .prefix("pre").specificParam(Struct.Dummy.fortyTwo, ["foo", "bar"]).finalize;
    assert(r == "final switch(sw) {
case Struct.Dummy.a: preA();break;
case Struct.Dummy.fortyTwo: preFortyTwo(foo, bar);break;
}", r);
}
