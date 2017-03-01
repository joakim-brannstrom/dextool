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

/// Generate the xml prelude.
void makePrelude(AppT)(ref AppT app) {
    import std.format : formattedWrite;

    formattedWrite(app, `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n");
}
