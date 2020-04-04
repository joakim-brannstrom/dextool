/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.schemata;

import logger = std.experimental.logger;
import std.algorithm : sort, map;
import std.array : empty;
import std.conv : to;
import std.datetime : Duration;
import std.exception : collectException;
import std.typecons : Tuple;

import process : DrainElement;
import sumtype;

import dextool.fsm : Fsm, next, act, get, TypeDataMap;

import dextool.plugin.mutate.backend.database : MutationStatusId, Database, spinSql;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, Blob;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner;
import dextool.plugin.mutate.backend.type : Mutation, TestCase, Checksum;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand;

@safe:

struct MutationTestResult {
    import std.datetime : Duration;
    import dextool.plugin.mutate.backend.database : MutationStatusId;
    import dextool.plugin.mutate.backend.type : TestCase;

    MutationStatusId id;
    Mutation.Status status;
    Duration testTime;
    TestCase[] testCases;
}

struct SchemataTestDriver {
    private {
        /// True as long as the schemata driver is running.
        bool isRunning_ = true;

        FilesysIO fio;

        Database* db;

        /// Runs the test commands.
        TestRunner* runner;

        /// Result of testing the mutants.
        MutationTestResult[] result_;
    }

    static struct None {
    }

    static struct Initialize {
    }

    static struct Done {
    }

    static struct NextMutantData {
        /// Mutants to test.
        MutationStatusId[] mutants;
    }

    static struct NextMutant {
        bool done;
        MutationStatusId id;
        Checksum checksum;
    }

    static struct TestMutantData {
        /// If the user has configured that the test cases should be analyzed.
        bool hasTestCaseOutputAnalyzer;
    }

    static struct TestMutant {
        MutationStatusId id;
        Checksum checksum;
        MutationTestResult result;
        bool hasTestOutput;
        // if there are mutants status id's related to a file but the mutants
        // have been removed.
        bool mutantIdError;
    }

    static struct TestCaseAnalyzeData {
        TestCaseAnalyzer* testCaseAnalyzer;
        DrainElement[] output;
    }

    static struct TestCaseAnalyze {
        MutationTestResult result;
        bool unstableTests;
    }

    static struct StoreResult {
        MutationTestResult result;
    }

    alias Fsm = dextool.fsm.Fsm!(None, Initialize, Done, NextMutant,
            TestMutant, TestCaseAnalyze, StoreResult);
    alias LocalStateDataT = Tuple!(TestMutantData, TestCaseAnalyzeData, NextMutantData);

    private {
        Fsm fsm;
        TypeDataMap!(LocalStateDataT, TestMutant, TestCaseAnalyze, NextMutant) local;
    }

    this(FilesysIO fio, TestRunner* runner, Database* db,
            TestCaseAnalyzer* testCaseAnalyzer, MutationStatusId[] mutants) {
        this.fio = fio;
        this.runner = runner;
        this.db = db;
        this.local.get!NextMutant.mutants = mutants;
        this.local.get!TestCaseAnalyze.testCaseAnalyzer = testCaseAnalyzer;
        this.local.get!TestMutant.hasTestCaseOutputAnalyzer = !testCaseAnalyzer.empty;
    }

    static void execute_(ref SchemataTestDriver self) @trusted {
        self.fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(NextMutant.init), (NextMutant a) {
            if (a.done)
                return fsm(Done.init);
            return fsm(TestMutant(a.id, a.checksum));
        }, (TestMutant a) {
            if (a.mutantIdError)
                return fsm(NextMutant.init);
            if (a.result.status == Mutation.Status.killed
                && self.local.get!TestMutant.hasTestCaseOutputAnalyzer && a.hasTestOutput) {
                return fsm(TestCaseAnalyze(a.result));
            }
            return fsm(StoreResult(a.result));
        }, (TestCaseAnalyze a) {
            if (a.unstableTests)
                return fsm(NextMutant.init);
            return fsm(StoreResult(a.result));
        }, (StoreResult a) => fsm(NextMutant.init), (Done a) => fsm(a));

        debug logger.trace("state: ", self.fsm.logNext);
        self.fsm.act!(self);
    }

nothrow:

    MutationTestResult[] result() {
        return result_;
    }

    void execute() {
        try {
            execute_(this);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    bool isRunning() {
        return isRunning_;
    }

    void opCall(None data) {
    }

    void opCall(Initialize data) {
    }

    void opCall(Done data) {
        isRunning_ = false;
    }

    void opCall(ref NextMutant data) {
        data.done = local.get!NextMutant.mutants.empty;

        if (!local.get!NextMutant.mutants.empty) {
            data.id = local.get!NextMutant.mutants[$ - 1];
            local.get!NextMutant.mutants = local.get!NextMutant.mutants[0 .. $ - 1];
            data.checksum = spinSql!(() { return db.getChecksum(data.id); });
        }
    }

    void opCall(ref TestMutant data) {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        import dextool.plugin.mutate.backend.analyze.pass_schemata : schemataMutantEnvKey,
            checksumToId;
        import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

        data.result.id = data.id;

        auto id = spinSql!(() { return db.getMutationId(data.id); });
        if (id.isNull) {
            data.mutantIdError = true;
            return;
        }
        auto entry_ = spinSql!(() { return db.getMutation(id.get); });
        if (entry_.isNull) {
            data.mutantIdError = true;
            return;
        }
        auto entry = entry_.get;

        try {
            const file = fio.toAbsoluteRoot(entry.file);
            auto original = fio.makeInput(file);
            auto txt = makeMutationText(original, entry.mp.offset,
                    entry.mp.mutations[0].kind, entry.lang);
            logger.infof("%s from '%s' to '%s' in %s:%s:%s", data.id, txt.original,
                    txt.mutation, file, entry.sloc.line, entry.sloc.column);
        } catch (Exception e) {
            logger.info(e.msg).collectException;
        }

        runner.env[schemataMutantEnvKey] = data.checksum.checksumToId.to!string;
        scope (exit)
            runner.env.remove(schemataMutantEnvKey);

        auto sw = StopWatch(AutoStart.yes);
        auto res = runTester(*runner);
        data.result.testTime = sw.peek;

        data.result.status = res.status;
        data.hasTestOutput = !res.output.empty;
        local.get!TestCaseAnalyze.output = res.output;

        logger.infof("%s %s (%s)", data.result.id, data.result.status,
                data.result.testTime).collectException;
    }

    void opCall(ref TestCaseAnalyze data) {
        try {
            auto analyze = local.get!TestCaseAnalyze.testCaseAnalyzer.analyze(
                    local.get!TestCaseAnalyze.output);
            local.get!TestCaseAnalyze.output = null;

            analyze.match!((TestCaseAnalyzer.Success a) {
                data.result.testCases = a.failed;
            }, (TestCaseAnalyzer.Unstable a) {
                logger.warningf("Unstable test cases found: [%-(%s, %)]", a.unstable);
                logger.info(
                    "As configured the result is ignored which will force the mutant to be re-tested");
                data.unstableTests = true;
            }, (TestCaseAnalyzer.Failed a) {
                logger.warning("The parser that analyze the output from test case(s) failed");
            });

            logger.infof(!data.result.testCases.empty, `%s killed by [%-(%s, %)]`,
                    data.result.id, data.result.testCases.sort.map!"a.name").collectException;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(StoreResult data) {
        result_ ~= data.result;
    }
}
