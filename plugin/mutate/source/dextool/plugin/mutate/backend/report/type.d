/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.type;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.type : MutationKind;

alias SimpleWriter = void delegate(const(char)[]) @safe;

/// Generic interface that a report event listeners shall implement.
@safe interface ReportEvent {
    void mutationKindEvent(const MutationKind[]);
    void locationStartEvent();
    void locationEvent(const ref IterateMutantRow);
    void locationEndEvent();
    void locationStatEvent();
    void statEvent(ref Database db);
}
