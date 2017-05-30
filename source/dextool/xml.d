/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Helper functions for xml reading and writing.
*/
module dextool.xml;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.type : FileName;

/// Generate the xml prelude.
void makePrelude(AppT)(ref AppT app) {
    import std.format : formattedWrite;

    formattedWrite(app, `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n");
}

/// Parse an xml file.
Nullable!T readRawConfig(T, alias parseFunc)(FileName fname) @trusted nothrow {
    static import std.file;
    import std.utf : validate;
    import std.xml;

    string msg;
    Nullable!T rval;

    try {
        string fin = cast(string) std.file.read(fname);
        validate(fin);
        check(fin);
        auto xml = new DocumentParser(fin);

        rval = parseFunc(xml);
        return rval;
    }
    catch (CheckException ex) {
        try {
            msg = ex.toString;
        }
        catch (Exception ex) {
            msg = ex.msg;
        }
    }
    catch (Exception ex) {
        msg = ex.msg;
    }

    try {
        logger.errorf("Invalid xml file '%s'", cast(string) fname);
        logger.error(msg);
    }
    catch (Exception ex) {
    }

    return rval;
}
