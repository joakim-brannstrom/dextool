/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.graphml.backend.interface_;

@safe interface Controller {
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(const string filename);
}

@safe interface Parameters {
}

/// Data produced by the backend to be handled by the frontend.
@safe interface Products {
}
