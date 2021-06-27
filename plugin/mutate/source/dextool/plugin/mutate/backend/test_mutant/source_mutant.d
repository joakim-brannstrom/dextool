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
import std.algorithm : sort, map, filter, among;
import std.array : empty, array;
import std.exception : collectException;
import std.path : buildPath;

import miniorm : spinSql;
import my.fsm : next, act, get, TypeDataMap;
import my.hash : Checksum64;
import my.named_type;
import my.optional;
import my.set;
import proc : DrainElement;
import sumtype;

static import my.fsm;

import dextool.plugin.mutate.backend.database : Database, MutationEntry, ChecksumTestCmdOriginal;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, Blob;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner, SkipTests;
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

    // Hash of current test binaries
    HashFile[string] testBinaryHashes;

    static struct Global {
        FilesysIO fio;
        Database* db;

        /// The mutant to apply.
        MutationEntry mutp;

        /// Runs the test commands.
        TestRunner* runner;

        TestBinaryDb* testBinaryDb;

        NamedType!(bool, Tag!"UseSkipMutant", bool.init, TagStringable) useSkipMutant;

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
        Optional!(Mutation.Status) calcStatus;
    }

    // if checksums of test binaries is used to set the status.
    static struct MarkCalcStatus {
        Mutation.Status status;
    }

    static struct RestoreCode {
        NamedType!(bool, Tag!"FilesysError", bool.init, TagStringable, ImplicitConvertable) filesysError;
    }

    static struct TestBinaryAnalyze {
        NamedType!(bool, Tag!"HasTestOutput", bool.init, TagStringable, ImplicitConvertable) hasTestOutput;
    }

    static struct TestCaseAnalyzeData {
        TestCaseAnalyzer* testCaseAnalyzer;
    }

    static struct TestCaseAnalyze {
        bool unstableTests;
    }

    static struct StoreResult {
    }

    static struct Propagate {
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

    alias Fsm = my.fsm.Fsm!(None, Initialize, MutateCode, TestMutant, RestoreCode, TestCaseAnalyze, StoreResult, Done,
            FilesysError, NoResultRestoreCode, NoResult, MarkCalcStatus,
            TestBinaryAnalyze, Propagate);
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

        if (logger.globalLogLevel.among(logger.LogLevel.trace, logger.LogLevel.all))
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
            if (a.calcStatus.hasValue)
                return fsm(MarkCalcStatus(a.calcStatus.orElse(Mutation.Status.unknown)));
            return fsm(TestBinaryAnalyze(a.hasTestOutput));
        }, (TestBinaryAnalyze a) {
            if (self.global.testResult.status == Mutation.Status.killed
                && self.local.get!TestMutant.hasTestCaseOutputAnalyzer && a.hasTestOutput) {
                return fsm(TestCaseAnalyze.init);
            }
            return fsm(RestoreCode.init);
        }, (TestCaseAnalyze a) {
            if (a.unstableTests)
                return fsm(NoResultRestoreCode.init);
            return fsm(RestoreCode.init);
        }, (MarkCalcStatus a) => RestoreCode.init, (RestoreCode a) {
            if (a.filesysError)
                return fsm(FilesysError.init);
            return fsm(StoreResult.init);
        }, (StoreResult a) => Propagate.init, (Propagate a) => Done.init,
                (Done a) => fsm(a), (FilesysError a) => fsm(a),
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
                    logger.infof("from '%s' to '%s' in %s:%s:%s",
                            cast(const(char)[]) mut_res.from, cast(const(char)[]) mut_res.to,
                            global.mutateFile, global.mutp.sloc.line, global.mutp.sloc.column);
                    logger.trace(global.mutp.id).collectException;
                } catch (Exception e) {
                    logger.warningf("%s %s", global.mutp.id, e.msg);
                }
                break;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.mutationError.get = true;
        }
    }

    void opCall(ref TestMutant data) @trusted {
        {
            scope (exit)
                () { global.swCompile.stop; global.swTest.start; }();

            bool successCompile;
            compile(local.get!TestMutant.buildCmd,
                    local.get!TestMutant.buildCmdTimeout, PrintCompileOnFailure(false)).match!(
                    (Mutation.Status a) { global.testResult.status = a; }, (bool success) {
                successCompile = success;
            },);

            if (!successCompile)
                return;
        }

        Set!string skipTests;
        if (!global.testBinaryDb.empty) {
            bool allOriginal = !global.testBinaryDb.original.empty;
            bool allAlive = !global.testBinaryDb.mutated.empty;
            bool anyKill;
            bool loopRun;
            try {
                foreach (f; global.runner.testCmds.map!(a => a.cmd.value[0]).hashFiles) {
                    loopRun = true;

                    if (f.cs in global.testBinaryDb.original) {
                        skipTests.add(f.file);
                        logger.tracef("match original %s %s", f.file, f.cs);
                    } else {
                        allOriginal = false;
                        testBinaryHashes[f.file] = f;
                    }

                    if (auto v = f.cs in global.testBinaryDb.mutated) {
                        logger.tracef("match mutated %s:%s %s", *v, f.file, f.cs);

                        allAlive = allAlive && *v == Mutation.Status.alive;
                        anyKill = anyKill || *v == Mutation.Status.killed;

                        if ((*v).among(Mutation.Status.alive, Mutation.Status.killed))
                            skipTests.add(f.file);
                    } else {
                        allAlive = false;
                    }
                }
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }

            if (!loopRun) {
                logger.trace("failed to checksum test_cmds: ",
                        global.runner.testCmds.map!(a => a.cmd)).collectException;
            } else if (allOriginal) {
                data.calcStatus = some(Mutation.Status.equivalent);
            } else if (anyKill) {
                data.calcStatus = some(Mutation.Status.killed);
            } else if (allAlive) {
                data.calcStatus = some(Mutation.Status.alive);
            } else if (skipTests.length == global.testBinaryDb.original.length) {
                // happens when there is a mix of alive or original
                data.calcStatus = some(Mutation.Status.alive);
            }

            // TODO: prefix with debug after 2021-10-23
            logger.tracef("allOriginal:%s allAlive:%s anyKill:%s dbLen:%s", allOriginal, allAlive, anyKill,
                    global.testBinaryDb.mutated.length + global.testBinaryDb.original.length)
                .collectException;
        }

        if (data.calcStatus.hasValue) {
            logger.info("Using mutant status from previous test executions").collectException;
        } else if (!skipTests.empty && !global.testBinaryDb.empty) {
            logger.infof("%s/%s test_cmd unaffected by mutant", skipTests.length,
                    global.testBinaryDb.original.length).collectException;
            logger.trace("skipped tests ", skipTests.toRange).collectException;
        }

        if (!data.calcStatus.hasValue) {
            global.testResult = runTester(*global.runner, SkipTests(skipTests));
            data.hasTestOutput.get = !global.testResult.output.empty;
        }
    }

    void opCall(TestBinaryAnalyze data) {
        scope (exit)
            testBinaryHashes = null;

        // means that the user has configured that it should be used because
        // then at least original is set.
        if (!global.testBinaryDb.empty) {
            final switch (global.testResult.status) with (Mutation) {
            case Status.alive:
                foreach (a; testBinaryHashes.byKeyValue) {
                    logger.tracef("save %s -> %s", a.key, Status.alive).collectException;
                    global.testBinaryDb.add(a.value.cs, Status.alive);
                }
                break;
            case Status.killed:
                foreach (a; global.testResult.output.byKey.map!(a => a.value[0])) {
                    if (auto v = a in testBinaryHashes) {
                        logger.tracef("save %s -> %s", a,
                                global.testResult.status).collectException;
                        global.testBinaryDb.add(v.cs, global.testResult.status);
                    }
                }
                break;
            case Status.timeout:
                goto case;
            case Status.noCoverage:
                goto case;
            case Status.killedByCompiler:
                goto case;
            case Status.equivalent:
                goto case;
            case Status.skipped:
                goto case;
            case Status.unknown:
                break;
            }
        }
    }

    void opCall(ref TestCaseAnalyze data) {
        scope (exit)
            global.testResult.output = null;

        foreach (testCmd; global.testResult.output.byKeyValue) {
            try {
                auto analyze = local.get!TestCaseAnalyze.testCaseAnalyzer.analyze(testCmd.key,
                        testCmd.value);

                analyze.match!((TestCaseAnalyzer.Success a) {
                    global.testCases ~= a.failed ~ a.testCmd;
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
    }

    void opCall(MarkCalcStatus data) {
        global.testResult.output = null;
        global.testResult.status = data.status;
    }

    void opCall(StoreResult data) {
        const statusId = spinSql!(() => global.db.mutantApi.getMutationStatusId(global.mutp.id));

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

        logger.infof("%s:%s (%s)", global.testResult.status,
                global.testResult.exitStatus.get, profile).collectException;
        logger.infof(!global.testCases.empty, `killed by [%-(%s, %)]`,
                global.testCases.sort.map!"a.name").collectException;
    }

    void opCall(Propagate data) {
        import std.algorithm : canFind;

        // only SDL mutants are supported for propgatation for now because a
        // surviving SDL is a strong indication that all internal mutants will
        // survive. The SDL mutant have basically deleted the code so. Note
        // though that there are probably corner cases wherein this assumption
        // isn't true.

        if (!global.useSkipMutant.get || result.empty
                || result[0].status != Mutation.Status.alive
                || global.mutp.mp.mutations.canFind!(a => a.kind != Mutation.Kind.stmtDel))
            return;

        logger.trace("Propagate").collectException;

        void propagate() {
            const fid = global.db.getFileId(global.mutp.file);
            if (fid.isNull)
                return;

            foreach (const stId; global.db.mutantApi.mutantsInRegion(fid.get,
                    global.mutp.mp.offset, Mutation.Status.unknown).filter!(a => a != result[0].id)) {
                const mutId = global.db.mutantApi.getMutationId(stId);
                if (mutId.isNull)
                    return;
                result ~= MutationTestResult(mutId.get, stId, Mutation.Status.skipped,
                        MutantTimeProfile.init, null, ExitStatus(0));
            }

            logger.tracef("Marked %s as skipped", result.length - 1).collectException;
        }

        spinSql!(() @trusted {
            auto t = global.db.transaction;
            propagate;
            t.commit;
        });
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
