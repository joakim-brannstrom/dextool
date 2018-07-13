/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

TODO:
*/

module dextool.plugin.eqdetect.backend.type;

struct ErrorResult {
    char[][] inputdata;
    char[] status;
}

import dextool.plugin.mutate.backend.type : Language;

struct Mutation {
    string path;
    int offset_begin;
    int offset_end;
    int kind;
    Language lang;
    int id;
}
