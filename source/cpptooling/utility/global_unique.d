/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Contains facilities to generate globally unique numbers.
*/
module cpptooling.utility.global_unique;

private shared(size_t) _nextSequence;

static this() {
    // Use a fixed number to minimize the difference between two sets of
    // generated data.
    //
    // Keeping it fixed to make it easier to debug, read the logs. Aka
    // reproduce the result.
    //
    // It is extremly important to minimize differences.
    // Diffs are used as the basis to evaluate changes.
    // No diff, no evaluation needed from an architectural point of view.
    // A change? Further inspection needed.
    _nextSequence = 42;
}

size_t nextNumber() @trusted nothrow {
    import core.atomic;

    size_t rval;

    synchronized {
        if (_nextSequence == size_t.max) {
            _nextSequence = size_t.min;
        }

        core.atomic.atomicOp!"+="(_nextSequence, 1);
        rval = _nextSequence;
    }

    return rval;
}
