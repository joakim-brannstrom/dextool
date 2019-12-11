/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.type;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow,
    FileRow, FileMutantRow;
import dextool.plugin.mutate.type : MutationKind;

alias SimpleWriter = void delegate(const(char)[]) @safe;

/** Generic interface that a reporter can implement.
 *
 * Event order:
 *  * mutationKindEvent
 *  * locationStatEvent
 *  * locationEvent. Looping over every mutant.
 *  * locationEndEvent
 *  * locationStatEvent
 *  * statEvent
 */
@safe interface ReportEvent {
    /// The printer is informed of what kind of mutants there are.
    void mutationKindEvent(const MutationKind[]);
    void locationStartEvent(ref Database db);
    void locationEvent(const ref IterateMutantRow);
    void locationEndEvent();
    void locationStatEvent();
    void statEvent(ref Database db);
}

/** Iterate over all mutants in a file.
 */
@safe interface FileReport {
    /// A mutant in that file.
    void fileMutantEvent(const ref FileMutantRow);

    /// The file has finished being processed.
    void endFileEvent(ref Database db);
}

/** Iterate over all files.
 */
@safe interface FilesReporter {
    /// The users input of what mutants to report.
    void mutationKindEvent(const MutationKind[]);

    /// Get the reporter that should be used to report all mutants in a file.
    FileReport getFileReportEvent(ref Database db, const ref FileRow);

    /// All files have been reported.
    void postProcessEvent(ref Database db);

    /// The last event to be called.
    /// Sync any IO if needed before destruction.
    void endEvent(ref Database db);
}
