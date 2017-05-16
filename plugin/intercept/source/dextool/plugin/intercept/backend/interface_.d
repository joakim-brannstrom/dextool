/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.intercept.backend.interface_;

import dsrcgen.cpp : CppModule, CppHModule;
import dsrcgen.sh : ShScriptModule;

import cpptooling.testdouble.header_filter : LocationType;

import dextool.type : FileName, DirName, MainName, StubPrefix, DextoolVersion,
    CustomHeader, MainNs, MainInterface;
import cpptooling.data.type : LocationTag;

struct FileData {
    import dextool.type : FileName;

    FileName filename;
    string data;
}

/** Control various aspectes of the analyze and generation like what nodes to
 * process.
 */
@safe interface Controller {
    /** Query the controller for a decision if it shall be processed. */
    bool doSymbol(string symbol);
}

@safe interface Parameters {
    static struct Files {
        FileName hdr;
        FileName impl;
        FileName script;
    }

    /// Files to write generated test double data to.
    Files getFiles();

    /// Output directory to store files in.
    DirName getOutputDirectory();

    /// Dextool Tool version.
    DextoolVersion getToolVersion();

    /// Custom header to prepend generated files with.
    CustomHeader getCustomHeader();

    /** A list of includes for the test double header.
     *
     * Part of the controller because they are dynamic, may change depending on
     * for example calls to doFile.
     */
    FileName[] getIncludes();

    /// The prefix to use for a symbol.
    StubPrefix symbolPrefix(string symbol);
}

/// Data produced by the generator like files.
@safe interface Products {
    /** Data pushed from the generator to be written to files.
     *
     * The put value is the code generation tree. It allows the caller of
     * Generator to inject more data in the tree before writing. For example a
     * custom header.
     *
     * Params:
     *   fname = file the content is intended to be written to.
     *   hdr_data = data to write to the file.
     */
    void putFile(FileName fname, CppHModule data);

    /// ditto.
    void putFile(FileName fname, CppModule data);

    /// ditto.
    void putFile(FileName fname, ShScriptModule data);

    /** During the translation phase the location of symbols that aren't
     * filtered out are pushed to the variant.
     *
     * It is intended that the variant control the #include directive strategy.
     * Just the files that was input?
     * Deduplicated list of files where the symbols was found?
     */
    void putLocation(FileName loc, LocationType type);
}
