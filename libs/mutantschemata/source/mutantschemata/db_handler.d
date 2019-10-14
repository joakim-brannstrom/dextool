/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

File for handling the db connection
*/
module mutantschemata.db_handler;

import std.meta : Alias;
import std.array : array;
import std.algorithm.iteration : map;

import mutantschemata.type : DSchemataMutant;
import mutantschemata.externals : SchemataMutant;
import mutantschemata.utility : convertToDSchemataMutant, convertToSchemataMutant;

import miniorm : Miniorm, buildSchema, delete_, insert, insertOrReplace, select;
import dextool.type : AbsolutePath;

alias DSM = Alias!(DSchemataMutant);
alias SM = Alias!(SchemataMutant);

struct DBHandler {
    private Miniorm db;

    this(AbsolutePath dbPath) {
        db = Miniorm(dbPath);
    }

    void insertInDB(SM sm) {
        db.run(insert!DSM.insert, convertToDSchemataMutant(sm));
    }

    void insertOrReplaceInDB(SchemataMutant sm) {
        db.run(insertOrReplace!DSM, convertToDSchemataMutant(sm));
    }

    SM[] selectFromDB(string condition = "") {
        auto query = db.run(select!DSM.where(condition));
        return query.map!(a => convertToSchemataMutant(a)).array;
    }

    void buildSchemaDB() {
        db.run(buildSchema!DSM);
    }

    void deleteInDB(string condition = "") {
        db.run(delete_!DSM.where(condition));
    }

    void closeDB() {
        db.close();
    }
}
