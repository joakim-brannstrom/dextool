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
import std.array : empty, appender;
import std.exception : collectException;
import std.json : JSONValue;
import std.path : buildPath;

import my.from_;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, FileRow, FileMutantRow, MutationId;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : FileReport, FilesReporter;
import dextool.plugin.mutate.backend.report.utility : window, windowSize;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportSection;

@safe:

void report(ref Database db, const MutationKind[] userKinds, const ConfigReport conf,
        FilesysIO fio, ref Diff diff) {
    import dextool.plugin.mutate.backend.database : FileMutantRow;
    import dextool.plugin.mutate.backend.mutation_type : toInternal;
    import dextool.plugin.mutate.backend.utility : Profile;

    const kinds = toInternal(userKinds);

    auto fps = new ReportJson(kinds, conf, fio, diff);

    fps.mutationKindEvent(userKinds);

    foreach (f; db.getDetailedFiles) {
        auto profile = Profile("generate report for " ~ f.file);

        fps.getFileReportEvent(db, f);

        void fn(const ref FileMutantRow row) {
            fps.fileMutantEvent(row);
        }

        db.iterateFileMutants(kinds, f.file, &fn);

        fps.endFileEvent;
    }

    auto profile = Profile("post process report");
    fps.postProcessEvent(db);
}

/**
 * Expects locations to be grouped by file.
 *
 * TODO this is ugly. Use a JSON serializer instead.
 */
final class ReportJson {
    import std.array : array;
    import std.algorithm : map, joiner, among;
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

        sections = conf.reportSection.toSet;
    }

    void mutationKindEvent(const MutationKind[] kinds) {
        report = ["types": kinds.map!(a => a.to!string).array, "files": []];
    }

    void getFileReportEvent(ref Database db, const ref FileRow fr) @trusted {
        current_file = fr;
    }

    void fileMutantEvent(const ref FileMutantRow r) @trusted {
        auto appendMutant() {
            JSONValue m = ["mutation_id" : r.id.to!long];
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
                && r.mutation.status.among(Mutation.Status.alive, Mutation.Status.noCoverage)
                || sections.contains(ReportSection.killed)
                && r.mutation.status == Mutation.Status.killed) {
            appendMutant;
        }
    }

    void endFileEvent() @trusted {
        if (current_file_mutants.empty) {
            return;
        }

        JSONValue s;
        s = [
            "filename": current_file.file,
            "checksum": format("%x", current_file.fileChecksum),
        ];
        s["mutants"] = JSONValue(current_file_mutants), report["files"].array ~= s;

        current_file_mutants = null;
    }

    void postProcessEvent(ref Database db) @trusted {
        import std.datetime : Clock;
        import std.path : buildPath;
        import std.stdio : File;
        import dextool.plugin.mutate.backend.report.analyzers : reportStatistics,
            reportDiff, DiffReport, reportMutationScoreHistory,
            reportDeadTestCases, reportTestCaseStats, reportTestCaseUniqueness,
            reportTrendByCodeChange;

        if (ReportSection.summary in sections) {
            const stat = reportStatistics(db, kinds);
            JSONValue s = ["alive" : stat.alive];
            s.object["no_coverage"] = stat.noCoverage;
            s.object["alive_nomut"] = stat.aliveNoMut;
            s.object["killed"] = stat.killed;
            s.object["timeout"] = stat.timeout;
            s.object["untested"] = stat.untested;
            s.object["killed_by_compiler"] = stat.killedByCompiler;
            s.object["total"] = stat.total;
            s.object["score"] = stat.score;
            s.object["nomut_score"] = stat.suppressedOfTotal;
            s.object["total_compile_time_s"] = stat.totalTime.compile.total!"seconds";
            s.object["total_test_time_s"] = stat.totalTime.test.total!"seconds";
            s.object["killed_by_compiler_time_s"] = stat.killedByCompilerTime.sum.total!"seconds";
            s.object["predicted_done"] = (Clock.currTime + stat.predictedDone).toISOExtString;
            s.object["worklist"] = stat.worklist;

            report["stat"] = s;
        }

        if (ReportSection.diff in sections) {
            auto r = reportDiff(db, kinds, diff, fio.getOutputDir);
            JSONValue s = ["score" : r.score];
            report["diff"] = s;
        }

        if (ReportSection.trend in sections) {
            const history = reportMutationScoreHistory(db);
            const byCodeChange = reportTrendByCodeChange(db, kinds);
            JSONValue d;
            d["code_change_score"] = byCodeChange.value.get;
            d["code_change_score_error"] = byCodeChange.error.get;

            d["history_score"] = history.estimate.predScore;
            d["score_history"] = toJson(history);
            report["trend"] = d;
        }

        if (ReportSection.tc_killed_no_mutants in sections) {
            auto r = reportDeadTestCases(db);
            JSONValue s;
            s["ratio"] = r.ratio;
            s["number"] = r.testCases.length;
            s["test_cases"] = r.testCases.map!(a => a.name).array;
            report["killed_no_mutants"] = s;
        }

        if (ReportSection.tc_stat in sections) {
            auto r = reportTestCaseStats(db, kinds);
            JSONValue s;
            foreach (a; r.testCases.byValue) {
                JSONValue v = ["ratio" : a.ratio];
                v["killed"] = a.info.killedMutants;
                s[a.tc.name] = v;
            }

            if (!r.testCases.empty) {
                report["test_case_stat"] = s;
            }
        }

        if (ReportSection.tc_unique in sections) {
            auto r = reportTestCaseUniqueness(db, kinds);
            if (!r.uniqueKills.empty) {
                JSONValue s;
                foreach (a; r.uniqueKills.byKeyValue) {
                    s[a.key.name] = a.value.map!((a => a.get)).array;
                }
                report["test_case_unique"] = s;
            }

            if (!r.noUniqueKills.empty) {
                report["test_case_no_unique"] = r.noUniqueKills.map!(a => a.name).array;
            }
        }

        File(buildPath(logDir, "report.json"), "w").write(report.toJSON(true));
    }
}

private:

import dextool.plugin.mutate.backend.report.analyzers : MutationScoreHistory;

JSONValue[] toJson(const MutationScoreHistory data) {
    import std.conv : to;

    auto app = appender!(JSONValue[])();
    foreach (a; data.data) {
        JSONValue s;
        s["date"] = a.timeStamp.to!string;
        s["score"] = a.score.get;
        app.put(s);
    }

    return app.data;
}
