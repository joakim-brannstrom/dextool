/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.internal;

import logger = std.experimental.logger;

import dextool.type : Path;

public import dextool.plugin.mutate.backend.type : Token;

@safe:

/// Presents an interface that returns the tokens in the file.
interface TokenStream {
    /// All tokens.
    Token[] getTokens(Path p) scope;

    /// All tokens except comments.
    Token[] getFilteredTokens(Path p) scope;
}
