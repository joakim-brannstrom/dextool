/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.backend.interface_;

import dsrcgen.cpp : CppModule, CppHModule;

import cpptooling.type : CustomHeader;
import dextool.io : WriteStrategy;
import dextool.type : DextoolVersion, Path;

/** Control various aspects of the analyze and generation like what nodes to
 * process.
 */
@safe interface Controller {
    /// Query the controller with the filename of the symbol for a decision
    /// if it shall be processed.
    bool doSymbolAtLocation(const string filename, const string symbol);

    /** Query the controller for a decision if it shall be processed. */
    bool doSymbol(string symbol);
}

/** Transformations that are governed by user input or other factors the
 * backend is unaware of.
 */
@safe interface Transform {
    /// Returns: the transformed name to a filename suitable for a header.
    Path createHeaderFile(string name);

    /// Returns: the transformed name to a filename suitable for an implementation.
    Path createImplFile(string name);

    /// Returns: path where to write the raw initial corpora for fuzzing
    /// based on the number of total parameters.
    Path createFuzzyDataFile(string name);

    /// Returns: path for xml config to be written to.
    Path createXmlConfigFile(string name);

    /// Returns: A unique filename.
    Path createFuzzCase(string name, ulong id);
}

/// Static parameters that are not changed while the backend is working.
@safe interface Parameter {
    /// Dextool Tool version.
    DextoolVersion getToolVersion();

    /// Custom header to prepend generated files with.
    CustomHeader getCustomHeader();
}

/// Data produced by the generator like files.
@safe interface Product {
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
    void putFile(Path fname, CppHModule data);

    /// ditto.
    void putFile(Path fname, CppModule data, WriteStrategy strategy = WriteStrategy.overwrite);

    /// Raw data to be written.
    void putFile(Path fname, const(ubyte)[] data);

    /// Raw data to be written.
    void putFile(Path fname, string data, WriteStrategy strategy = WriteStrategy.overwrite);
}
