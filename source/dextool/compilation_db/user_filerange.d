/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This is a handy range to interate over either all files from the user OR all
files in a compilation database.
*/
module dextool.compilation_db.user_filerange;

import logger = std.experimental.logger;

import dextool.compilation_db : CompileCommandFilter, CompileCommandDB, parseFlag, SearchResult;
import dextool.type : FileName, AbsolutePath;

@safe:

struct UserFileRange {
    import std.typecons : Nullable;
    import dextool.compilation_db : SearchResult, ParseFlags;

    enum RangeOver {
        inFiles,
        database
    }

    this(CompileCommandDB db, string[] in_files, string[] cflags,
            const CompileCommandFilter ccFilter) {
        this.db = db;
        this.cflags = cflags;
        this.ccFilter = ccFilter;
        this.inFiles = in_files;

        if (in_files.length == 0) {
            kind = RangeOver.database;
        } else {
            kind = RangeOver.inFiles;
        }
    }

    const RangeOver kind;
    CompileCommandDB db;
    string[] inFiles;
    string[] cflags;
    const CompileCommandFilter ccFilter;

    Nullable!SearchResult front() {
        assert(!empty, "Can't get front of an empty range");

        typeof(return) curr;

        final switch (kind) {
        case RangeOver.inFiles:
            if (db.length > 0) {
                curr = db.findFlags(FileName(inFiles[0]), cflags, ccFilter);
            } else {
                curr = SearchResult(cflags.dup, AbsolutePath(FileName(inFiles[0])));
            }
            break;
        case RangeOver.database:
            curr = SearchResult(db.payload[0].parseFlag(ccFilter),
                    db.payload[0].absoluteFile);
            curr.flags.cflags = cflags ~ curr.flags.cflags;
            break;
        }

        return curr;
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");

        final switch (kind) {
        case RangeOver.inFiles:
            inFiles = inFiles[1 .. $];
            break;
        case RangeOver.database:
            db.payload = db.payload[1 .. $];
            break;
        }
    }

    bool empty() @safe pure nothrow const @nogc {
        final switch (kind) {
        case RangeOver.inFiles:
            return inFiles.length == 0;
        case RangeOver.database:
            return db.length == 0;
        }
    }

    size_t length() @safe pure nothrow const @nogc {
        final switch (kind) {
        case RangeOver.inFiles:
            return inFiles.length;
        case RangeOver.database:
            return db.length;
        }
    }
}

private:

import std.typecons : Nullable;

/// Find flags for fname by searching in the compilation DB.
Nullable!SearchResult findFlags(ref CompileCommandDB compdb, FileName fname,
        const string[] flags, ref const CompileCommandFilter flag_filter) {
    import dextool.compilation_db : appendOrError;

    auto rval = compdb.appendOrError(flags, fname, flag_filter);
    logger.error(rval.isNull, "Unable to find any compiler flags for: ", fname);
    return rval;
}
