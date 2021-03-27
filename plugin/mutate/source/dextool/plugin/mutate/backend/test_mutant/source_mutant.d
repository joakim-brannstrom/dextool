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

import core.time : Duration;
import logger = std.experimental.logger;
import std.algorithm : sort, map;
import std.array : empty, array;
import std.exception : collectException;
import std.path : buildPath;

import my.fsm : next, act, get, TypeDataMap;
import my.named_type;
import proc : DrainElement;
import sumtype;

static import my.fsm;

import dextool.plugin.mutate.backend.database : Database, MutationEntry;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, Blob;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner;
import dextool.plugin.mutate.backend.type : Mutation, TestCase;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.type : ShellCommand;
import dextool.type : AbsolutePath, Path;

@safe:

/** Drive the control flow when testing **a** mutant.
 */
struct MutationTestDriver {
    import std.datetime.stopwatch : StopWatch;
    import std.typecons : Tuple;

    static struct Global {
        FilesysIO fio;
        Database* db;

        /// The mutant to apply.
        MutationEntry mutp;

        /// Runs the test commands.
        TestRunner* runner;

        /// File to mutate.
        AbsolutePath mutateFile;

        /// The original file.
        Blob original;

        /// The result of running the test cases.
        TestResult testResult;

        /// Test cases that killed the mutant.
        TestCase[] testCases;

        /// How long it took to do the mutation testing.
        StopWatch swCompile;
        StopWatch swTest;
    }

    static struct None {
    }

    static struct Initialize {
    }

    static struct MutateCode {
        NamedType!(bool, Tag!"FilesysError", bool.init, TagStringable, ImplicitConvertable) filesysError;
        NamedType!(bool, Tag!"MutationError", bool.init, TagStringable, ImplicitConvertable) mutationError;
    }

    static struct TestMutantData {
        /// If the user has configured that the test cases should be analyzed.
        bool hasTestCaseOutputAnalyzer;
        ShellCommand buildCmd;
        Duration buildCmdTimeout;
    }

    static struct TestMutant {
        NamedType!(bool, Tag!"HasTestOutput", bool.init, TagStringable, ImplicitConvertable) hasTestOutput;
    }

    static struct RestoreCode {
        NamedType!(bool, Tag!"FilesysError", bool.init, TagStringable, ImplicitConvertable) filesysError;
    }

    static struct TestCaseAnalyzeData {
        TestCaseAnalyzer* testCaseAnalyzer;
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

    alias Fsm = my.fsm.Fsm!(None, Initialize, MutateCode, TestMutant, RestoreCode,
            TestCaseAnalyze, StoreResult, Done, FilesysError, NoResultRestoreCode, NoResult);
    alias LocalStateDataT = Tuple!(TestMutantData, TestCaseAnalyzeData);

    private {
        Fsm fsm;
        Global global;
        TypeDataMap!(LocalStateDataT, TestMutant, TestCaseAnalyze) local;
        bool isRunning_ = true;
        bool stopBecauseError_;
    }

    MutationTestResult[] result;

    this(Global global, TestMutantData l1, TestCaseAnalyzeData l2) {
        this.global = global;
        this.local = LocalStateDataT(l1, l2);

        if (logger.globalLogLevel == logger.LogLevel.trace)
            fsm.logger = (string s) { logger.trace(s); };
    }

    static void execute_(ref MutationTestDriver self) @trusted {
        self.fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(MutateCode.init), (MutateCode a) {
            if (a.filesysError)
                return fsm(FilesysError.init);
            else if (a.mutationError)
                return fsm(NoResultRestoreCode.init);
            return fsm(TestMutant.init);
        }, (TestMutant a) {
            if (self.global.testResult.status == Mutation.Status.killed
                && self.local.get!TestMutant.hasTestCaseOutputAnalyzer && a.hasTestOutput) {
                return fsm(TestCaseAnalyze.init);
            }
            return fsm(RestoreCode.init);
        }, (TestCaseAnalyze a) {
            if (a.unstableTests)
                return fsm(NoResultRestoreCode.init);
            return fsm(RestoreCode.init);
        }, (RestoreCode a) {
            if (a.filesysError)
                return fsm(FilesysError.init);
            return fsm(StoreResult.init);
        }, (StoreResult a) { return fsm(Done.init); }, (Done a) => fsm(a),
                (FilesysError a) => fsm(a),
                (NoResultRestoreCode a) => fsm(NoResult.init), (NoResult a) => fsm(a),);

        self.fsm.act!self;
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
        global.swCompile.start;
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
            global.mutateFile = AbsolutePath(buildPath(global.fio.getOutputDir, global.mutp.file));
            global.original = global.fio.makeInput(global.mutateFile);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            logger.warning("Unable to read ", global.mutateFile).collectException;
            data.filesysError.get = true;
            return;
        }

        // mutate
        try {
            auto fout = global.fio.makeOutput(global.mutateFile);
            auto mut_res = generateMutant(*global.db, global.mutp, global.original, fout);

            final switch (mut_res.status) with (GenerateMutantStatus) {
            case error:
                data.mutationError.get = true;
                break;
            case filesysError:
                data.filesysError.get = true;
                break;
            case databaseError:
                // such as when the database is locked
                data.mutationError.get = true;
                break;
            case checksumError:
                data.filesysError.get = true;
                break;
            case noMutation:
                data.mutationError.get = true;
                break;
            case ok:
                try {
                    logger.infof("%s from '%s' to '%s' in %s:%s:%s", global.mutp.id.get,
                            cast(const(char)[]) mut_res.from, cast(const(char)[]) mut_res.to,
                            global.mutateFile, global.mutp.sloc.line, global.mutp.sloc.column);

                } catch (Exception e) {
                    logger.warningf("Mutation ID %s %s", global.mutp.id.get, e.msg);
                }
                break;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.mutationError.get = true;
        }
    }

    void opCall(ref TestMutant data) {
        bool successCompile;
        compile(local.get!TestMutant.buildCmd, local.get!TestMutant.buildCmdTimeout).match!(
                (Mutation.Status a) { global.testResult.status = a; }, (bool success) {
            successCompile = success;
        },);

        global.swCompile.stop;
        global.swTest.start;

        if (!successCompile)
            return;

        global.testResult = runTester(*global.runner);

        data.hasTestOutput.get = !global.testResult.output.empty;
    }

    void opCall(ref TestCaseAnalyze data) {
        scope (exit)
            global.testResult.output = null;

        try {
            auto analyze = local.get!TestCaseAnalyze.testCaseAnalyzer.analyze(
                    global.testResult.output);

            analyze.match!((TestCaseAnalyzer.Success a) {
                global.testCases = a.failed;
                global.testCases ~= global.testResult.testCmds.map!(a => TestCase(a.get)).array;
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
        import miniorm : spinSql;

        const statusId = spinSql!(() => global.db.getMutationStatusId(global.mutp.id));

        global.swTest.stop;
        auto profile = MutantTimeProfile(global.swCompile.peek, global.swTest.peek);

        if (statusId.isNull) {
            logger.trace("No MutationStatusId for ", global.mutp.id.get).collectException;
            return;
        }

        result = [
            MutationTestResult(global.mutp.id, statusId.get, global.testResult.status,
                    profile, global.testCases, global.testResult.exitStatus)
        ];

        logger.infof("%s %s:%s (%s)", global.mutp.id.get, global.testResult.status,
                global.testResult.exitStatus.get, profile).collectException;
        logger.infof(!global.testCases.empty, `%s killed by [%-(%s, %)]`,
                global.mutp.id.get, global.testCases.sort.map!"a.name").collectException;
    }

    void opCall(ref RestoreCode data) {
        // restore the original file.
        try {
            global.fio.makeOutput(global.mutateFile).write(global.original.content);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            // fatal error because being unable to restore a file prohibit
            // future mutations.
            data.filesysError.get = true;
        }
    }
}
