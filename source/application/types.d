// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.types;

import std.typecons : Typedef;

enum ExitStatusType {
    Ok,
    Errors
}

enum LocationType {
    Root,
    Leaf
}

/** Prefix used for prepending generated code with a unique string to avoid
 * name collisions.
 * See specific functions for how it is used.
 */
alias StubPrefix = Typedef!(string, string.init, "StubPrefix");

/// Prefix used for prepending generated files.
alias FilePrefix = Typedef!(string, string.init, "StubPrefix");

alias MainFileName = Typedef!(string, string.init, "MainFileName");
alias MainName = Typedef!(string, string.init, "MainName");
alias MainNs = Typedef!(string, string.init, "MainNs");
alias MainInterface = Typedef!(string, string.init, "MainInterface");

alias DirName = Typedef!(string, string.init, "DirectoryName");

alias FileName = Typedef!(string, string.init, "FileName");
alias FileNames = Typedef!(string[], null, "FileNames");
