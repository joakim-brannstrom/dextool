/**
Copyright: Copyright (c) 2018, Nils Petersson & Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Nils Petersson (nilpe995@student.liu.se) & Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the database connection for eqdetect. It uses the d2sqlite3 package
to create and establish connection to the physical database by providing the path to it.

Mutation-struct:
A simplified version of the MutationEntry in mutate that handles the information needed
by dbhandler and SnippetFinder in codegenerator.d.

TODO:
- Use standalone db from mutate
- Possibly utilize MutationEntry instead of creating new struct
*/
module dextool.plugin.eqdetect.backend.dbhandler;

import d2sqlite3 : sqlDatabase = Database;
import std.format : format;
import std.typecons : Nullable, NullableRef, nullableRef;
import dextool.plugin.mutate.backend.type;
import dextool.plugin.eqdetect.backend.type : Mutation;

class DbHandler {
    string path;
    sqlDatabase db;

    this(string filepath) {
        path = filepath;
        db = sqlDatabase(path);
    }

    Mutation[] getMutations() {
        import std.path;

        // status could be user-input instead of hardcoded
        auto stmt = db.prepare(format("SELECT mp_id, kind, id FROM mutation WHERE status='2';"));
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

    Mutation getMutationPoint(Mutation mutation, string mp_id) {
        auto stmt = db.prepare(format("SELECT file_id, offset_begin, offset_end FROM mutation_point WHERE id='%s';",
                mp_id));
        auto res = stmt.execute;

        mutation = getFilePath(mutation, res.front.peek!string(0));
        mutation.offset_begin = res.front.peek!int(1);
        mutation.offset_end = res.front.peek!int(2);

        return mutation;
    }

    Mutation getFilePath(Mutation mutation, string file_id) {
        auto stmt = db.prepare(format("SELECT path, lang FROM files WHERE id='%s';", file_id));
        auto res = stmt.execute;

        import std.path;

        auto path = res.front.peek!string(0);
        path = buildPath("..", path);
        mutation.path = path;
        mutation.lang = res.front.peek!Language(1);

        return mutation;
    }

    void setEquivalence(int mutation_id, int status) {
        import std.conv;

        auto stmt = db.prepare(format("UPDATE mutation SET eq='%s' WHERE id='%s';",
                status, mutation_id));
        auto res = stmt.execute;
    }

}
