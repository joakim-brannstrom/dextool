// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.utility.conv;

/// Cast to a string.
string str(T)(const T value) @safe pure nothrow {
    return cast(string) value;
}
