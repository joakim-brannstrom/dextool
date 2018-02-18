/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.database.type;

import core.time : Duration;

import dextool.type : AbsolutePath, Path;

/// Primary key in the database
struct Pkey(Pkeys T) {
    long payload;
    alias payload this;
}

enum Pkeys {
    mutationId,
    fileId,
}

/// Primary key in the mutation table
alias MutationId = Pkey!(Pkeys.mutationId);
/// Primary key in the files table
alias FileId = Pkey!(Pkeys.fileId);

struct MutationEntry {
    import dextool.plugin.mutate.backend.type;

    MutationId id;
    Path file;
    SourceLoc sloc;
    MutationPoint mp;
    Duration timeSpentMutating;
}

struct NextMutationEntry {
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.type;

    enum Status {
        ok,
        queryError,
        done,
    }

    Status st;
    Nullable!MutationEntry entry;
}

struct MutationPointEntry {
    import dextool.plugin.mutate.backend.type;

    MutationPoint mp;
    Path file;
    SourceLoc sloc;
}

struct MutationReportEntry {
    import core.time : Duration;

    long count;
    Duration time;
}
