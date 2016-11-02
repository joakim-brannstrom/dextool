// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.types;

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
struct StubPrefix {
    string payload;
    alias payload this;
}

/// Prefix used for prepending generated files.
struct FilePrefix {
    string payload;
    alias payload this;
}

struct MainFileName {
    string payload;
    alias payload this;
}

struct MainName {
    string payload;
    alias payload this;
}

struct MainNs {
    string payload;
    alias payload this;
}

struct MainInterface {
    string payload;
    alias payload this;
}

struct DirName {
    string payload;
    alias payload this;
}

struct FileName {
    string payload;
    alias payload this;
}

//TODO remove FileNames
struct FileNames {
    string[] payload;
    alias payload this;
}

struct InFiles {
    string[] payload;
    alias payload this;
}

struct DextoolVersion {
    string payload;
    alias payload this;
}
