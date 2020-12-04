/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.json;

import logger = std.experimental.logger;
import std.array : empty;
import std.exception : collectException;
import std.path : buildPath;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, FileRow, FileMutantRow, MutationId;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : FileReport, FilesReporter;
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
final class ReportJson : FileReport, FilesReporter {
    import std.array : array;
    import std.algorithm : map, joiner;
    import std.conv : to;
    import std.format : format;
    import std.json;
    import my.set;

    const Mutation.Kind[] kinds;
    const AbsolutePath logDir;
    Set!ReportSection sections;
    FilesysIO fio;

    // Report alive mutants in this section
    Diff diff;

    JSONValue report;
    JSONValue[] current_file_mutants;
    FileRow current_file;

    this(const Mutation.Kind[] kinds, const ConfigReport conf, FilesysIO fio, ref Diff diff) {
        this.kinds = kinds;
        this.fio = fio;
        this.logDir = conf.logDir;
        this.diff = diff;

        sections = (conf.reportSection.length == 0 ? conf.reportLevel.toSections
                : conf.reportSection.dup).toSet;
    }

    override void mutationKindEvent(const MutationKind[] kinds) {
        report = ["types": kinds.map!(a => a.to!string).array, "files": []];
    }

    override FileReport getFileReportEvent(ref Database db, const ref FileRow fr) @trusted {
        current_file = fr;
        return this;
    }

    override void fileMutantEvent(const ref FileMutantRow r) @trusted {
        auto appendMutant() {
            JSONValue m = ["id": r.id.to!long];
            m.object["kind"] = r.mutation.kind.to!string;
            m.object["status"] = r.mutation.status.to!string;
            m.object["line"] = r.sloc.line;
            m.object["column"] = r.sloc.column;
            m.object["begin"] = r.mutationPoint.offset.begin;
            m.object["end"] = r.mutationPoint.offset.end;

            try {
                MakeMutationTextResult mut_txt;
                auto abs_path = AbsolutePath(buildPath(fio.getOutputDir, current_file.file.Path));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
                m.object["value"] = mut_txt.mutation;
            } catch (Exception e) {
                logger.warning(e.msg);
            }

            current_file_mutants ~= m;
        }

        if (sections.contains(ReportSection.all_mut) || sections.contains(ReportSection.alive)
                && r.mutation.status == Mutation.Status.alive
                || sections.contains(ReportSection.killed)
                && r.mutation.status == Mutation.Status.killed) {
            appendMutant;
        }
    }

    override void endFileEvent(ref Database db) @trusted {
        if (current_file_mutants.empty) {
            return;
        }

        JSONValue s;
        s = [
            "filename": current_file.file,
            "checksum": format("%x", current_file.fileChecksum),
        ];
        s["mutations"] = JSONValue(current_file_mutants), report["files"].array ~= s;

        current_file_mutants = null;
    }

    override void postProcessEvent(ref Database db) @trusted {
        import std.datetime : Clock;
        import std.path : buildPath;
        import std.stdio : File;
        import dextool.plugin.mutate.backend.report.analyzers : reportStatistics, reportDiff;
        import dextool.plugin.mutate.backend.report.analyzers : DiffReport, reportDiff;

        if (ReportSection.summary in sections) {
            const stat = reportStatistics(db, kinds);
            JSONValue s = ["alive": stat.alive];
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
            s.object["trendScore"] = stat.estimate.value.get;
            s.object["trendScoreError"] = stat.estimate.error.get;
            s.object["worklist"] = stat.worklist;

            report["stat"] = s;
        }

        if (ReportSection.diff in sections) {
            auto r = reportDiff(db, kinds, diff, fio.getOutputDir);
            JSONValue s = ["score": r.score];
            report["diff"] = s;
        }

        File(buildPath(logDir, "report.json"), "w").write(report.toJSON(true));
    }

    override void endEvent(ref Database) {
    }
}
