/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.common_actors;

import my.actor : typedActor;
import my.path : AbsolutePath;

import dextool.plugin.mutate.backend.database : dbOpenTimeout;
import dextool.plugin.mutate.backend.test_mutant.common : MutationTestResult;
import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutFsm;

// common messages

struct Init {
}

// actors

struct IsDone {
}

// Save test results to the database.
// dfmt off
alias DbSaveActor = typedActor!(
        // init the actor by opening the database.
        void function(Init, AbsolutePath dbPath),
        // save the result to the database
        void function(MutationTestResult result, TimeoutFsm timeoutFsm),
        void function(MutationTestResult result, long timeoutIter),
        // query if it has finished saving to the db.
        bool function(IsDone));
// dfmt on

struct GetMutantsLeft {
}

struct UnknownMutantTested {
}

struct Tick {
}

struct ForceUpdate {
}

// Progress statistics for the mutation testing such as how many that are left to test.
// dfmt off
alias StatActor = typedActor!(
        // init the actor by opening the database.
        void function(Init, AbsolutePath dbPath),
        long function(GetMutantsLeft),
        void function(Tick),
        // force an update of the statistics
        void function(ForceUpdate),
        // a mutant has been tested and is done
        void function(UnknownMutantTested, long));
// dfmt on
