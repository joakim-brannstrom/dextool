/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the database connection for eqdetect. It uses standalone.d file
in dextool mutate to create and establish connection to the physical database.

TODO:
- Separate database in dextool mutate into a more library structed package
*/
module dextool.plugin.eqdetect.backend.dbhandler;

import std.format : format;
import dextool.plugin.eqdetect.backend.type : Mutation;
import dextool.plugin.mutate.backend.database.standalone : SDatabase = Database;

private SDatabase sdb;

void initDB(string filepath) {
    import dextool.type : AbsolutePath;

    AbsolutePath abspath;
    abspath.payload = filepath;
    sdb.db = SDatabase.make(abspath);
}

Mutation[] getMutations() {
    import std.path : extension;

    // status could be user-input instead of hardcoded
    auto stmt = sdb.db.prepare(format("SELECT mp_id, kind, id FROM mutation WHERE status='2';"));
    auto mutations = stmt.execute;

    Mutation[] mutation_list;

    foreach (m; mutations) {
        Mutation mutation;
        mutation.kind = m.peek!int(1);
        mutation.id = m.peek!int(2);
        mutation = getMutationPoint(mutation, m.peek!string(0));

        if (extension(mutation.path) != ".h") {
            mutation_list = mutation_list ~ mutation;
        }
    }
    return mutation_list;
}

private Mutation getMutationPoint(Mutation mutation, string mp_id) {
    auto stmt = sdb.db.prepare(format(
            "SELECT file_id, offset_begin, offset_end FROM mutation_point WHERE id='%s';", mp_id));
    auto res = stmt.execute;

    mutation = getFilePath(mutation, res.front.peek!string(0));
    mutation.offset.begin = res.front.peek!int(1);
    mutation.offset.end = res.front.peek!int(2);

    return mutation;
}

private Mutation getFilePath(Mutation mutation, string file_id) {
    auto stmt = sdb.db.prepare(format("SELECT path, lang FROM files WHERE id='%s';", file_id));
    auto res = stmt.execute;

    import dextool.plugin.mutate.backend.type : Language;

    auto path = res.front.peek!string(0);

    import std.path : buildNormalizedPath;
    import std.file : getcwd;
    path = buildNormalizedPath(getcwd(), "..", path);

    mutation.path = path;
    mutation.lang = res.front.peek!Language(1);

    return mutation;
}

void setEquivalence(int mutation_id, int status) {
    auto stmt = sdb.db.prepare(format("UPDATE mutation SET eq='%s' WHERE id='%s';",
            status, mutation_id));
    auto res = stmt.execute;
}
