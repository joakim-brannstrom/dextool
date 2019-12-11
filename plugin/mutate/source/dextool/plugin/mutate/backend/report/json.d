/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.json;

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : ReportEvent;
import dextool.plugin.mutate.backend.report.utility : window, windowSize, toSections;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportSection;

@safe:

/**
 * Expects locations to be grouped by file.
 *
 * TODO this is ugly. Use a JSON serializer instead.
 */
final class ReportJson : ReportEvent {
    import std.array : array;
    import std.algorithm : map, joiner;
    import std.conv : to;
    import std.format : format;
    import std.json;
    import dextool.set;

    const Mutation.Kind[] kinds;
    const AbsolutePath logDir;
    Set!ReportSection sections;
    FilesysIO fio;

    JSONValue report;
    JSONValue current_file;

    Path last_file;

    this(const Mutation.Kind[] kinds, const ConfigReport conf, FilesysIO fio) {
        this.kinds = kinds;
        this.fio = fio;
        this.logDir = conf.logDir;

        sections = (conf.reportSection.length == 0 ? conf.reportLevel.toSections
                : conf.reportSection.dup).setFromList;
    }

    override void mutationKindEvent(const MutationKind[] kinds) {
        report = ["types": kinds.map!(a => a.to!string).array, "files": []];
    }

    override void locationStartEvent(ref Database db) {
    }

    override void locationEvent(const ref IterateMutantRow r) @trusted {
        bool new_file;

        if (last_file.length == 0) {
            current_file = [
                "filename": r.file,
                "checksum": format("%x", r.fileChecksum)
            ];
            new_file = true;
        } else if (last_file != r.file) {
            report["files"].array ~= current_file;
            current_file = [
                "filename": r.file,
                "checksum": format("%x", r.fileChecksum)
            ];
            new_file = true;
        }

        auto appendMutant() {
            JSONValue m = ["id" : r.id.to!long];
            m.object["kind"] = r.mutation.kind.to!string;
            m.object["status"] = r.mutation.status.to!string;
            m.object["line"] = r.sloc.line;
            m.object["column"] = r.sloc.column;
            m.object["begin"] = r.mutationPoint.offset.begin;
            m.object["end"] = r.mutationPoint.offset.end;

            try {
                MakeMutationTextResult mut_txt;
                auto abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
                m.object["value"] = mut_txt.mutation;
            } catch (Exception e) {
                logger.warning(e.msg);
            }
            if (new_file) {
                last_file = r.file;
                current_file.object["mutants"] = JSONValue([m]);
            } else {
                current_file["mutants"].array ~= m;
            }
        }

        if (sections.contains(ReportSection.all_mut) || sections.contains(ReportSection.alive)
                && r.mutation.status == Mutation.Status.alive
                || sections.contains(ReportSection.killed)
                && r.mutation.status == Mutation.Status.killed) {
            appendMutant;
        }
    }

    override void locationEndEvent() @trusted {
        report["files"].array ~= current_file;
    }

    override void locationStatEvent() {
    }

    override void statEvent(ref Database db) @trusted {
        import std.datetime : Clock;
        import std.path : buildPath;
        import std.stdio : File;
        import dextool.plugin.mutate.backend.report.analyzers : reportStatistics;

        if (sections.contains(ReportSection.summary)) {
            const stat = reportStatistics(db, kinds);
            JSONValue s = ["alive" : stat.alive];
            s.object["aliveNoMut"] = stat.aliveNoMut;
            s.object["killed"] = stat.killed;
            s.object["timeout"] = stat.timeout;
            s.object["untested"] = stat.untested;
            s.object["killedByCompiler"] = stat.killedByCompiler;
            s.object["total"] = stat.total;
            s.object["score"] = stat.score;
            s.object["nomutScore"] = stat.suppressedOfTotal;
            s.object["totalTime"] = stat.totalTime.total!"seconds";
            s.object["killedByCompilerTime"] = stat.killedByCompilerTime.total!"seconds";
            s.object["predictedDone"] = (Clock.currTime + stat.predictedDone).toISOExtString;

            report["stat"] = s;
        }

        File(buildPath(logDir, "report.json"), "w").write(report.toJSON(true));
    }
}
