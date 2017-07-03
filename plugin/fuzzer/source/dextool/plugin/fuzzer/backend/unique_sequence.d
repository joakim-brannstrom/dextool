/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains the plumbing for generating a unique sequence of numbers
that is tightly packed.
*/
module dextool.plugin.fuzzer.backend.unique_sequence;

import logger = std.experimental.logger;

/// The first number of the sequence will be skipped.
/// It is okey.
struct Sequence(NumT) {
    @disable this(this);

    /// Put a number into the pool or adjust `n` to a valid value.
    void putOrAdjust(ref NumT n) {
        if (n <= last_num) {
            n = next;
        } else if (auto v = n in used_pool) {
            n = next;
        } else {
            used_pool[n] = true;
        }

        if (n % 100 == 0) {
            vacuumPool;
        }
    }

    NumT next() {
        while (++last_num in used_pool) {
        }
        return last_num;
    }

    void vacuumPool() {
        bool[NumT] new_pool;

        foreach (n; used_pool) {
            if (n >= last_num)
                new_pool[n] = true;
        }

        used_pool = new_pool;
    }

private:
    bool[NumT] used_pool;
    NumT last_num;
}

version (unittest) {
    import unit_threaded : shouldEqual;
}

@("Shall be a list of numbers for the holes in the initialized sequence")
unittest {
    Sequence!ulong seq;

    ulong[] input = [0, 2, 4, 7];

    foreach (i; 0 .. input.length)
        seq.putOrAdjust(input[i]);

    ulong[] output;
    foreach (i; 0 .. 5)
        output ~= seq.next;

    input.shouldEqual([1, 2, 4, 7]);
    output.shouldEqual([3, 5, 6, 8, 9]);
}
