/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Test a mutant by modifying the source code.
*/
module dextool.plugin.mutate.backend.test_mutant.source_mutant;

import logger = std.experimental.logger;
import std.array : empty;
import std.exception : collectException;

import sumtype;
import process : DrainElement;

import dextool.fsm : Fsm, next, act, get, TypeDataMap;
import dextool.plugin.mutate.backend.database : Database, MutationEntry;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, Blob;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner;
import dextool.plugin.mutate.backend.type : Mutation, TestCase;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.type : ShellCommand;
import dextool.set;
import dextool.type : AbsolutePath, Path;

@safe:

/// The result of testing a mutant.
struct MutationTestResult {
    import std.datetime : Duration;
    import sumtype;
    import process : DrainElement;
    import dextool.plugin.mutate.backend.database : MutationId;
    import dextool.plugin.mutate.backend.type : TestCase;

    static struct NoResult {
    }

    static struct StatusUpdate {
        MutationId id;
        Mutation.Status status;
        Duration testTime;
        TestCase[] testCases;
        DrainElement[] output;
    }

    alias Value = SumType!(NoResult, StatusUpdate);
    Value value;

    void opAssign(MutationTestResult rhs) @trusted pure nothrow @nogc {
        this.value = rhs.value;
    }

    void opAssign(StatusUpdate rhs) @trusted pure nothrow @nogc {
        this.value = Value(rhs);
    }
}

/** Drive the control flow when testing **a** mutant.
 */
struct MutationTestDriver {
    import std.datetime.stopwatch : StopWatch;
    import std.typecons : Tuple;
    import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;

    static struct Global {
        FilesysIO fio;
        Database* db;

        /// The mutant to apply.
        MutationEntry mutp;

        /// Runs the test commands.
        TestRunner* runner;

        /// File to mutate.
        AbsolutePath mut_file;

        /// The original file.
        Blob original;

        /// The result of running the test cases.
        Mutation.Status mut_status;

        /// Test cases that killed the mutant.
        TestCase[] test_cases;

        /// How long it took to do the mutation testing.
        StopWatch sw;
    }

    static struct None {
    }

    static struct Initialize {
    }

    static struct MutateCode {
        bool next;
        bool filesysError;
        bool mutationError;
    }

    static struct TestMutantData {
        /// If the user has configured that the test cases should be analyzed.
        bool hasTestCaseOutputAnalyzer;
        ShellCommand compile_cmd;
        DrainElement[] output;
    }

    static struct TestMutant {
    }

    static struct RestoreCode {
        bool next;
        bool filesysError;
    }

    static struct TestCaseAnalyzeData {
        TestCaseAnalyzer* testCaseAnalyzer;
        DrainElement[] output;
    }

    static struct TestCaseAnalyze {
        bool unstableTests;
    }

    static struct StoreResult {
    }

    static struct Done {
    }

    static struct FilesysError {
    }

    // happens when an error occurs during mutations testing but that do not
    // prohibit testing of other mutants
    static struct NoResultRestoreCode {
    }

    static struct NoResult {
    }

    alias Fsm = dextool.fsm.Fsm!(None, Initialize, MutateCode, TestMutant, RestoreCode,
            TestCaseAnalyze, StoreResult, Done, FilesysError, NoResultRestoreCode, NoResult);
    alias LocalStateDataT = Tuple!(TestMutantData, TestCaseAnalyzeData);

    private {
        Fsm fsm;
        Global global;
        TypeDataMap!(LocalStateDataT, TestMutant, TestCaseAnalyze) local;
        bool isRunning_ = true;
        bool stopBecauseError_;
    }

    MutationTestResult result;

    this(Global global, TestMutantData l1, TestCaseAnalyzeData l2) {
        this.global = global;
        this.local = LocalStateDataT(l1, l2);
    }

    static void execute_(ref MutationTestDriver self) @trusted {
        self.fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(MutateCode.init), (MutateCode a) {
            if (a.next)
                return fsm(TestMutant.init);
            else if (a.filesysError)
                return fsm(FilesysError.init);
            else if (a.mutationError)
                return fsm(NoResultRestoreCode.init);
            return fsm(a);
        }, (TestMutant a) {
            if (self.global.mut_status == Mutation.Status.killed
                && self.local.get!TestMutant.hasTestCaseOutputAnalyzer
                && !self.local.get!TestMutant.output.empty) {
                self.local.get!TestCaseAnalyze.output = self.local.get!TestMutant.output;
                return fsm(TestCaseAnalyze.init);
            }
            return fsm(RestoreCode.init);
        }, (TestCaseAnalyze a) {
            if (a.unstableTests)
                return fsm(NoResultRestoreCode.init);
            return fsm(RestoreCode.init);
        }, (RestoreCode a) {
            if (a.next)
                return fsm(StoreResult.init);
            else if (a.filesysError)
                return fsm(FilesysError.init);
            return fsm(a);
        }, (StoreResult a) { return fsm(Done.init); }, (Done a) => fsm(a),
                (FilesysError a) => fsm(a),
                (NoResultRestoreCode a) => fsm(NoResult.init), (NoResult a) => fsm(a),);

        debug logger.info("state: ", self.fsm.logNext);
        self.fsm.act!(self);
        debug logger.info("end act: ", self.fsm.logAct);
    }

nothrow:

    void execute() {
        try {
            execute_(this);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    /// Returns: true as long as the driver is processing a mutant.
    bool isRunning() {
        return isRunning_;
    }

    bool stopBecauseError() {
        return stopBecauseError_;
    }

    void opCall(None data) {
    }

    void opCall(Initialize data) {
        global.sw.start;
    }

    void opCall(Done data) {
        isRunning_ = false;
    }

    void opCall(FilesysError data) {
        logger.warning("Filesystem error").collectException;
        isRunning_ = false;
        stopBecauseError_ = true;
    }

    void opCall(NoResultRestoreCode data) {
        RestoreCode tmp;
        this.opCall(tmp);
    }

    void opCall(NoResult data) {
        isRunning_ = false;
    }

    void opCall(ref MutateCode data) {
        import dextool.plugin.mutate.backend.generate_mutant : generateMutant,
            GenerateMutantResult, GenerateMutantStatus;

        try {
            global.mut_file = AbsolutePath(Path(global.mutp.file), global.fio.getOutputDir);
            global.original = global.fio.makeInput(global.mut_file);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            logger.warning("Unable to read ", global.mut_file).collectException;
            data.filesysError = true;
            return;
        }

        // mutate
        try {
            auto fout = global.fio.makeOutput(global.mut_file);
            auto mut_res = generateMutant(*global.db, global.mutp, global.original, fout);

            final switch (mut_res.status) with (GenerateMutantStatus) {
            case error:
                data.mutationError = true;
                break;
            case filesysError:
                data.filesysError = true;
                break;
            case databaseError:
                // such as when the database is locked
                data.mutationError = true;
                break;
            case checksumError:
                data.filesysError = true;
                break;
            case noMutation:
                data.mutationError = true;
                break;
            case ok:
                data.next = true;
                try {
                    logger.infof("%s from '%s' to '%s' in %s:%s:%s", global.mutp.id,
                            cast(const(char)[]) mut_res.from, cast(const(char)[]) mut_res.to,
                            global.mut_file, global.mutp.sloc.line, global.mutp.sloc.column);

                } catch (Exception e) {
                    logger.warning("Mutation ID", e.msg);
                }
                break;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.mutationError = true;
        }
    }

    void opCall(ref TestMutant data) {
        global.mut_status = Mutation.Status.unknown;
        local.get!TestMutant.output = null;

        bool successCompile;
        compile(local.get!TestMutant.compile_cmd).match!((Mutation.Status a) {
            global.mut_status = a;
        }, (bool success) { successCompile = success; },);

        if (!successCompile)
            return;

        auto res = runTester(*global.runner);
        global.mut_status = res.status;
        local.get!TestMutant.output = res.output;
    }

    void opCall(ref TestCaseAnalyze data) {
        global.test_cases = null;

        try {
            auto analyze = local.get!TestCaseAnalyze.testCaseAnalyzer.analyze(
                    local.get!TestCaseAnalyze.output);
            local.get!TestCaseAnalyze.output = null;

            analyze.match!((TestCaseAnalyzer.Success a) {
                global.test_cases = a.failed;
            }, (TestCaseAnalyzer.Unstable a) {
                logger.warningf("Unstable test cases found: [%-(%s, %)]", a.unstable);
                logger.info(
                    "As configured the result is ignored which will force the mutant to be re-tested");
                data.unstableTests = true;
            }, (TestCaseAnalyzer.Failed a) {
                logger.warning("The parser that analyze the output from test case(s) failed");
            });
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(StoreResult data) {
        global.sw.stop;
        result = MutationTestResult.StatusUpdate(global.mutp.id,
                global.mut_status, global.sw.peek, global.test_cases);
    }

    void opCall(ref RestoreCode data) {
        // restore the original file.
        try {
            global.fio.makeOutput(global.mut_file).write(global.original.content);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            // fatal error because being unable to restore a file prohibit
            // future mutations.
            data.filesysError = true;
            return;
        }

        data.next = true;
    }
}
