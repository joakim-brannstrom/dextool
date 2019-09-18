/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant;

import core.thread : Thread;
import core.time : Duration, dur;
import std.datetime : SysTime;
import std.typecons : Nullable, NullableRef, nullableRef;
import std.exception : collectException;

import logger = std.experimental.logger;

import blob_model : Blob, Uri;

import dextool.fsm : Fsm, next, act;
import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    NextMutationEntry, spinSqlQuery;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin;
import dextool.type : AbsolutePath, ShellCommand, ExitStatusType, FileName, DirName;

@safe:

auto makeTestMutant() {
    return BuildTestMutant();
}

private:

struct BuildTestMutant {
@safe:
nothrow:

    import dextool.plugin.mutate.type : MutationKind;

    private struct InternalData {
        Mutation.Kind[] mut_kinds;
        FilesysIO filesys_io;
        ConfigMutationTest config;
    }

    private InternalData data;

    auto config(ConfigMutationTest c) {
        data.config = c;
        return this;
    }

    auto mutations(MutationKind[] v) {
        import dextool.plugin.mutate.backend.utility : toInternal;

        data.mut_kinds = toInternal(v);
        return this;
    }

    ExitStatusType run(ref Database db, FilesysIO fio) nothrow {
        auto mutationFactory(DriverData d, Duration test_base_timeout) @safe nothrow {
            import std.typecons : Unique;
            import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;

            try {
                auto global = MutationTestDriver.Global(d.filesysIO, d.db, d.autoCleanup,
                        d.mutKind, d.conf.mutationCompile, d.conf.mutationTester,
                        d.conf.mutationTestCaseAnalyze,
                        d.conf.mutationTestCaseBuiltin, test_base_timeout);
                // TODO: this may not be needed.
                global.test_cases = new GatherTestCase;
                return Unique!MutationTestDriver(new MutationTestDriver(global));
            } catch (Exception e) {
                logger.error(e.msg).collectException;
            }
            assert(0, "should not happen");
        }

        // trusted because the lifetime of the database is guaranteed to outlive any instances in this scope
        auto db_ref = () @trusted { return nullableRef(&db); }();

        auto driver_data = DriverData(db_ref, fio, data.mut_kinds, new AutoCleanup, data.config);

        auto test_driver = TestDriver2!mutationFactory(driver_data);

        while (test_driver.isRunning) {
            test_driver.execute;
        }

        return test_driver.status;
    }
}

immutable stdoutLog = "stdout.log";
immutable stderrLog = "stderr.log";

struct DriverData {
    NullableRef!Database db;
    FilesysIO filesysIO;
    Mutation.Kind[] mutKind;
    AutoCleanup autoCleanup;
    ConfigMutationTest conf;
}

/** Run the test suite to verify a mutation.
 *
 * Params:
 *  p = ?
 *  timeout = timeout threshold.
 */
Mutation.Status runTester(WatchdogT)(ShellCommand compile_p, ShellCommand tester_p,
        AbsolutePath test_output_dir, WatchdogT watchdog, FilesysIO fio) nothrow {
    import std.algorithm : among;
    import std.datetime.stopwatch : StopWatch;
    import dextool.plugin.mutate.backend.linux_process : spawnSession, tryWait, kill, wait;
    import std.stdio : File;
    import core.sys.posix.signal : SIGKILL;
    import dextool.plugin.mutate.backend.utility : rndSleep;

    Mutation.Status rval;

    try {
        auto p = spawnSession(compile_p.program ~ compile_p.arguments);
        auto res = p.wait;
        if (res.terminated && res.status != 0)
            return Mutation.Status.killedByCompiler;
        else if (!res.terminated) {
            logger.warning("unknown error when executing the compiler").collectException;
            return Mutation.Status.unknown;
        }
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    string stdout_p;
    string stderr_p;

    if (test_output_dir.length != 0) {
        import std.path : buildPath;

        stdout_p = buildPath(test_output_dir, stdoutLog);
        stderr_p = buildPath(test_output_dir, stderrLog);
    }

    try {
        auto p = spawnSession(tester_p.program ~ tester_p.arguments, stdout_p, stderr_p);
        // trusted: killing the process started in this scope
        void cleanup() @safe nothrow {
            import core.sys.posix.signal : SIGKILL;

            if (rval.among(Mutation.Status.timeout, Mutation.Status.unknown)) {
                kill(p, SIGKILL);
                wait(p);
            }
        }

        scope (exit)
            cleanup;

        rval = Mutation.Status.timeout;
        watchdog.start;
        while (watchdog.isOk) {
            auto res = tryWait(p);
            if (res.terminated) {
                if (res.status == 0)
                    rval = Mutation.Status.alive;
                else
                    rval = Mutation.Status.killed;
                break;
            }

            rndSleep(10.dur!"msecs", 50);
        }
    } catch (Exception e) {
        // unable to for example execute the test suite
        logger.warning(e.msg).collectException;
        return Mutation.Status.unknown;
    }

    return rval;
}

struct MeasureTestDurationResult {
    ExitStatusType status;
    Duration runtime;
}

/**
 * If the tests fail (exit code isn't 0) any time then they are too unreliable
 * to use for mutation testing.
 *
 * The runtime is the lowest of the three executions.
 *
 * Params:
 *  p = ?
 */
MeasureTestDurationResult measureTesterDuration(ShellCommand cmd) nothrow {
    if (cmd.program.length == 0) {
        collectException(logger.error("No test suite runner specified (--mutant-tester)"));
        return MeasureTestDurationResult(ExitStatusType.Errors);
    }

    auto any_failure = ExitStatusType.Ok;

    void fun() {
        import std.process : execute;

        auto res = execute(cmd.program ~ cmd.arguments);
        if (res.status != 0)
            any_failure = ExitStatusType.Errors;
    }

    import std.datetime.stopwatch : benchmark;
    import std.algorithm : minElement, map;
    import core.time : dur;

    try {
        auto bench = benchmark!fun(3);

        if (any_failure != ExitStatusType.Ok)
            return MeasureTestDurationResult(ExitStatusType.Errors);

        auto a = (cast(long)((bench[0].total!"msecs") / 3.0)).dur!"msecs";
        return MeasureTestDurationResult(ExitStatusType.Ok, a);
    } catch (Exception e) {
        collectException(logger.error(e.msg));
        return MeasureTestDurationResult(ExitStatusType.Errors);
    }
}

/** Drive the control flow when testing **a** mutant.
 */
struct MutationTestDriver {
    import std.datetime.stopwatch : StopWatch;
    import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;

    static struct Global {
        FilesysIO fio;
        NullableRef!Database db;
        AutoCleanup auto_cleanup;
        const(Mutation.Kind)[] mut_kind;
        ShellCommand compile_cmd;
        ShellCommand test_cmd;
        AbsolutePath test_case_cmd;
        const TestCaseAnalyzeBuiltin[] tc_analyze_builtin;
        Duration tester_runtime;

        Nullable!MutationEntry mutp;
        AbsolutePath mut_file;
        Blob original;

        /// Temporary directory where stdout/stderr should be written.
        AbsolutePath test_tmp_output;

        Mutation.Status mut_status;

        GatherTestCase test_cases;

        StopWatch sw;
    }

    static struct None {
    }

    static struct Initialize {
    }

    static struct MutateCode {
        bool next;
        bool allMutantsTested;
        bool filesysError;
        bool mutationError;
    }

    static struct TestMutant {
        bool next;
        bool mutationError;
    }

    static struct RestoreCode {
        bool next;
        bool filesysError;
    }

    static struct TestCaseAnalyze {
        bool next;
        bool mutationError;
        bool unstableTests;
    }

    static struct StoreResult {
    }

    static struct Done {
    }

    static struct AllMutantsTested {
    }

    static struct FilesysError {
    }

    // happens when an error occurs during mutations testing but that do not
    // prohibit testing of other mutants
    static struct NoResultRestoreCode {
    }

    static struct NoResult {
    }

    alias Fsm = dextool.fsm.Fsm!(None, Initialize, MutateCode, TestMutant, RestoreCode, TestCaseAnalyze,
            StoreResult, Done, AllMutantsTested, FilesysError, NoResultRestoreCode, NoResult);
    Fsm fsm;
    Global global;

    this(Global global) {
        this.global = global;
    }

    void execute_() {
        fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(MutateCode.init), (MutateCode a) {
            if (a.next)
                return fsm(TestMutant.init);
            else if (a.allMutantsTested)
                return fsm(AllMutantsTested.init);
            else if (a.filesysError)
                return fsm(FilesysError.init);
            else if (a.mutationError)
                return fsm(NoResultRestoreCode.init);
            return fsm(a);
        }, (TestMutant a) {
            if (a.next)
                return fsm(TestCaseAnalyze.init);
            else if (a.mutationError)
                return fsm(NoResultRestoreCode.init);
            return fsm(a);
        }, (TestCaseAnalyze a) {
            if (a.next)
                return fsm(RestoreCode.init);
            else if (a.mutationError || a.unstableTests)
                return fsm(NoResultRestoreCode.init);
            return fsm(a);
        }, (RestoreCode a) {
            if (a.next)
                return fsm(StoreResult.init);
            else if (a.filesysError)
                return fsm(FilesysError.init);
            return fsm(a);
        }, (StoreResult a) { return fsm(Done.init); }, (Done a) => fsm(a),
                (AllMutantsTested a) => fsm(a), (FilesysError a) => fsm(a),
                (NoResultRestoreCode a) => fsm(NoResult.init), (NoResult a) => fsm(a),);

        fsm.act!((None a) {}, (Initialize a) { global.sw.start; }, this, (Done a) {
        }, (AllMutantsTested a) {}, (FilesysError a) {
            logger.warning("Filesystem error").collectException;
        }, (NoResultRestoreCode a) { RestoreCode tmp; this.opCall(tmp); }, (NoResult a) {
        },);
    }

nothrow:

    void execute() {
        try {
            this.execute_();
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    /// Returns: true as long as the driver is processing a mutant.
    bool isRunning() {
        return !fsm.isState!(Done, NoResult, FilesysError, AllMutantsTested);
    }

    bool stopBecauseError() {
        return fsm.isState!(FilesysError);
    }

    bool stopMutationTesting() {
        return fsm.isState!(AllMutantsTested);
    }

    void opCall(ref MutateCode data) {
        import core.thread : Thread;
        import std.random : uniform;
        import dextool.plugin.mutate.backend.generate_mutant : generateMutant,
            GenerateMutantResult, GenerateMutantStatus;

        auto next_m = spinSqlQuery!(() {
            return global.db.nextMutation(global.mut_kind);
        });
        if (next_m.st == NextMutationEntry.Status.done) {
            logger.info("Done! All mutants are tested").collectException;
            data.allMutantsTested = true;
            return;
        } else {
            global.mutp = next_m.entry;
        }

        try {
            global.mut_file = AbsolutePath(FileName(global.mutp.get.file),
                    DirName(global.fio.getOutputDir));
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
            auto mut_res = generateMutant(global.db.get, global.mutp.get, global.original, fout);

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
                    logger.infof("%s from '%s' to '%s' in %s:%s:%s", global.mutp.get.id,
                            cast(const(char)[]) mut_res.from, cast(const(char)[]) mut_res.to,
                            global.mut_file, global.mutp.get.sloc.line,
                            global.mutp.get.sloc.column);

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
        import dextool.type : Path;

        // TODO: move mutp to the state local data.
        assert(!global.mutp.isNull);

        if (global.test_case_cmd.length != 0 || global.tc_analyze_builtin.length != 0) {
            try {
                auto tmpdir = createTmpDir(global.mutp.get.id);
                if (tmpdir.length == 0) {
                    data.mutationError = true;
                    return;
                }
                global.test_tmp_output = Path(tmpdir).AbsolutePath;
                global.auto_cleanup.add(global.test_tmp_output);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
                data.mutationError = true;
                return;
            }
        }

        try {
            import dextool.plugin.mutate.backend.watchdog : StaticTime;

            auto watchdog = StaticTime!StopWatch(global.tester_runtime);

            global.mut_status = runTester(global.compile_cmd, global.test_cmd,
                    global.test_tmp_output, watchdog, global.fio);
            data.next = true;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.mutationError = true;
        }
    }

    void opCall(ref TestCaseAnalyze data) {
        import std.algorithm : splitter, map, filter;
        import std.array : array;
        import std.ascii : newline;
        import std.file : exists;
        import std.path : buildPath;
        import std.process : execute;
        import std.string : strip;

        if (global.mut_status != Mutation.Status.killed || global.test_tmp_output.length == 0) {
            data.next = true;
            return;
        }

        try {
            auto stdout_ = buildPath(global.test_tmp_output, stdoutLog);
            auto stderr_ = buildPath(global.test_tmp_output, stderrLog);

            if (!exists(stdout_) || !exists(stderr_)) {
                logger.warningf("Unable to open %s and %s for test case analyze", stdout_, stderr_);
                data.mutationError = true;
                return;
            }

            auto gather_tc = new GatherTestCase;

            // the post processer must succeeed for the data to be stored. if
            // is considered a major error that may corrupt existing data if it
            // fails.
            bool success = true;

            if (global.test_case_cmd.length != 0) {
                success = success && externalProgram([
                        global.test_case_cmd, stdout_, stderr_
                        ], gather_tc);
            }
            if (global.tc_analyze_builtin.length != 0) {
                success = success && builtin(global.fio.getOutputDir, [
                        stdout_, stderr_
                        ], global.tc_analyze_builtin, gather_tc);
            }

            if (gather_tc.unstable.length != 0) {
                logger.warningf("Unstable test cases found: [%-(%s, %)]",
                        gather_tc.unstableAsArray);
                logger.info(
                        "As configured the result is ignored which will force the mutant to be re-tested");
                data.unstableTests = true;
            } else if (success) {
                global.test_cases = gather_tc;
                // TODO: this is stupid... do not use bools
                data.next = true;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(StoreResult data) {
        import std.algorithm : sort, map;

        global.sw.stop;

        const cnt_action = () {
            if (global.mut_status == Mutation.Status.alive)
                return Database.CntAction.incr;
            return Database.CntAction.reset;
        }();

        spinSqlQuery!(() {
            global.db.updateMutation(global.mutp.get.id, global.mut_status,
                global.sw.peek, global.test_cases.failedAsArray, cnt_action);
        });

        logger.infof("%s %s (%s)", global.mutp.get.id, global.mut_status,
                global.sw.peek).collectException;
        logger.infof(global.test_cases.failed.length != 0, `%s killed by [%-(%s, %)]`,
                global.mutp.get.id, global.test_cases.failedAsArray.sort.map!"a.name")
            .collectException;
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

        if (global.test_tmp_output.length != 0) {
            import std.file : rmdirRecurse;

            // trusted: test_tmp_output is tested to be valid data.
            () @trusted {
                try {
                    rmdirRecurse(global.test_tmp_output);
                } catch (Exception e) {
                    logger.info(e.msg).collectException;
                }
            }();
        }

        data.next = true;
    }
}

struct TestDriver2(alias mutationDriverFactory) {
    import std.typecons : Unique;
    import dextool.plugin.mutate.backend.watchdog : ProgressivWatchdog;

    static struct Global {
        DriverData data;
        ProgressivWatchdog prog_wd;
        Unique!MutationTestDriver mut_driver;
        long last_timeout_mutant_count = long.max;
    }

    static struct None {
    }

    static struct Initialize {
    }

    static struct SanityCheck {
        bool sanityCheckFailed;
    }

    static struct UpdateAndResetAliveMutants {
    }

    static struct ResetOldMutants {
    }

    static struct CleanupTempDirs {
    }

    static struct CheckMutantsLeft {
        bool allMutantsTested;
    }

    static struct PreCompileSut {
        bool compilationError;
    }

    static struct MeasureTestSuite {
        bool unreliableTestSuite;
    }

    static struct PreMutationTest {
    }

    static struct MutationTest {
        bool next;
        bool mutationError;
        bool allMutantsTested;
    }

    static struct CheckTimeout {
        bool next;
        bool timeoutUnchanged;
    }

    static struct IncrWatchdog {
    }

    static struct ResetTimeout {
        bool next;
    }

    static struct Done {
    }

    static struct Error {
    }

    alias Fsm = dextool.fsm.Fsm!(None, Initialize, SanityCheck,
            UpdateAndResetAliveMutants, ResetOldMutants, CleanupTempDirs,
            CheckMutantsLeft, PreCompileSut, MeasureTestSuite, PreMutationTest,
            MutationTest, CheckTimeout, IncrWatchdog, ResetTimeout, Done, Error);

    Fsm fsm;
    Global global;

    this(DriverData data) {
        this.global = Global(data);
    }

    void execute_() {
        fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(SanityCheck.init), (SanityCheck a) {
            if (a.sanityCheckFailed)
                return fsm(Error.init);
            return fsm(PreCompileSut.init);
        }, (UpdateAndResetAliveMutants a) => fsm(ResetOldMutants.init),
                (ResetOldMutants a) => fsm(CheckMutantsLeft.init),
                (CleanupTempDirs a) => fsm(PreMutationTest.init), (CheckMutantsLeft a) {
            if (a.allMutantsTested)
                return fsm(Done.init);
            return fsm(MeasureTestSuite.init);
        }, (PreCompileSut a) {
            if (a.compilationError)
                return fsm(Error.init);
            return fsm(UpdateAndResetAliveMutants.init);
        }, (MeasureTestSuite a) {
            if (a.unreliableTestSuite)
                return fsm(Error.init);
            return fsm(CleanupTempDirs.init);
        }, (PreMutationTest a) => fsm(MutationTest.init), (MutationTest a) {
            if (a.next)
                return fsm(CleanupTempDirs.init);
            else if (a.allMutantsTested)
                return fsm(CheckTimeout.init);
            else if (a.mutationError)
                return fsm(Error.init);
            return fsm(a);
        }, (CheckTimeout a) {
            if (a.next)
                return fsm(IncrWatchdog.init);
            else if (a.timeoutUnchanged)
                return fsm(Done.init);
            return fsm(a);
        }, (IncrWatchdog a) => fsm(ResetTimeout.init), (ResetTimeout a) {
            if (a.next)
                return fsm(CleanupTempDirs.init);
            return fsm(a);
        }, (Done a) => fsm(a), (Error a) => fsm(a),);

        fsm.act!((None a) {}, (Initialize a) {}, this,);
    }

nothrow:
    void execute() {
        try {
            this.execute_();
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    bool isRunning() {
        return !fsm.isState!(Done, Error);
    }

    ExitStatusType status() {
        if (fsm.isState!Done)
            return ExitStatusType.Ok;
        return ExitStatusType.Errors;
    }

    void opCall(Done data) {
        global.data.autoCleanup.cleanup;
    }

    void opCall(Error data) {
        global.data.autoCleanup.cleanup;
    }

    void opCall(ref SanityCheck data) {
        // #SPC-sanity_check_db_vs_filesys
        import dextool.type : Path;
        import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath;
        import dextool.plugin.mutate.backend.type : Checksum;

        const(Path)[] files;
        spinSqlQuery!(() { files = global.data.db.getFiles; });

        bool has_sanity_check_failed;
        for (size_t i; i < files.length;) {
            Checksum db_checksum;
            spinSqlQuery!(() {
                db_checksum = global.data.db.getFileChecksum(files[i]);
            });

            try {
                auto abs_f = AbsolutePath(FileName(files[i]),
                        DirName(cast(string) global.data.filesysIO.getOutputDir));
                auto f_checksum = checksum(global.data.filesysIO.makeInput(abs_f).content[]);
                if (db_checksum != f_checksum) {
                    logger.errorf("Mismatch between the file on the filesystem and the analyze of '%s'",
                            abs_f);
                    has_sanity_check_failed = true;
                }
            } catch (Exception e) {
                // assume it is a problem reading the file or something like that.
                has_sanity_check_failed = true;
                logger.trace(e.msg).collectException;
            }

            // all done. continue with the next file
            ++i;
        }

        if (has_sanity_check_failed) {
            data.sanityCheckFailed = true;
            logger.error("Detected that one or more file has changed since last analyze where done")
                .collectException;
            logger.error("Either restore the files to the previous state or rerun the analyzer")
                .collectException;
        } else {
            logger.info("Sanity check passed. Files on the filesystem are consistent")
                .collectException;
        }
    }

    // TODO: refactor. This method is too long.
    void opCall(UpdateAndResetAliveMutants data) {
        import core.time : dur;
        import std.algorithm : map;
        import std.datetime.stopwatch : StopWatch;
        import std.path : buildPath;
        import dextool.type : Path;
        import dextool.plugin.mutate.backend.type : TestCase;

        if (global.data.conf.mutationTestCaseAnalyze.length == 0
                && global.data.conf.mutationTestCaseBuiltin.length == 0)
            return;

        AbsolutePath test_tmp_output;
        try {
            auto tmpdir = createTmpDir(0);
            if (tmpdir.length == 0)
                return;
            test_tmp_output = Path(tmpdir).AbsolutePath;
            global.data.autoCleanup.add(test_tmp_output);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            return;
        }

        TestCase[] all_found_tc;

        try {
            import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;
            import dextool.plugin.mutate.backend.watchdog : StaticTime;

            auto stdout_ = buildPath(test_tmp_output, stdoutLog);
            auto stderr_ = buildPath(test_tmp_output, stderrLog);

            // using an unreasonable timeout because this is more intended to reuse the functionality in runTester
            auto watchdog = StaticTime!StopWatch(999.dur!"hours");
            runTester(global.data.conf.mutationCompile, global.data.conf.mutationTester,
                    test_tmp_output, watchdog, global.data.filesysIO);

            auto gather_tc = new GatherTestCase;

            if (global.data.conf.mutationTestCaseAnalyze.length != 0) {
                externalProgram([
                        global.data.conf.mutationTestCaseAnalyze, stdout_, stderr_
                        ], gather_tc);
                logger.warningf(gather_tc.unstable.length != 0,
                        "Unstable test cases found: [%-(%s, %)]", gather_tc.unstableAsArray);
            }
            if (global.data.conf.mutationTestCaseBuiltin.length != 0) {
                builtin(global.data.filesysIO.getOutputDir, [stdout_, stderr_],
                        global.data.conf.mutationTestCaseBuiltin, gather_tc);
            }

            all_found_tc = gather_tc.foundAsArray;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        warnIfConflictingTestCaseIdentifiers(all_found_tc);

        // the test cases before anything has potentially changed.
        Set!string old_tcs;
        spinSqlQuery!(() {
            foreach (tc; global.data.db.getDetectedTestCases)
                old_tcs.add(tc.name);
        });

        final switch (global.data.conf.onRemovedTestCases) with (
            ConfigMutationTest.RemovedTestCases) {
        case doNothing:
            spinSqlQuery!(() {
                global.data.db.addDetectedTestCases(all_found_tc);
            });
            break;
        case remove:
            import dextool.plugin.mutate.backend.database : MutationStatusId;

            MutationStatusId[] ids;
            spinSqlQuery!(() {
                ids = global.data.db.setDetectedTestCases(all_found_tc);
            });
            foreach (id; ids)
                spinSqlQuery!(() {
                    global.data.db.updateMutationStatus(id, Mutation.Status.unknown);
                });
            break;
        }

        Set!string found_tcs;
        spinSqlQuery!(() {
            found_tcs = null;
            foreach (tc; global.data.db.getDetectedTestCases)
                found_tcs.add(tc.name);
        });

        printDroppedTestCases(old_tcs, found_tcs);

        const new_test_cases = hasNewTestCases(old_tcs, found_tcs);

        if (new_test_cases
                && global.data.conf.onNewTestCases == ConfigMutationTest.NewTestCases.resetAlive) {
            logger.info("Resetting alive mutants").collectException;
            resetAliveMutants(global.data.db);
        }
    }

    void opCall(ResetOldMutants data) {
        import dextool.plugin.mutate.backend.database.type;

        if (global.data.conf.onOldMutants == ConfigMutationTest.OldMutant.nothing)
            return;

        logger.infof("Resetting the %s oldest mutants",
                global.data.conf.oldMutantsNr).collectException;
        MutationStatusTime[] oldest;
        spinSqlQuery!(() {
            oldest = global.data.db.getOldestMutants(global.data.mutKind,
                global.data.conf.oldMutantsNr);
        });
        foreach (const old; oldest) {
            logger.info("  Last updated ", old.updated).collectException;
            spinSqlQuery!(() {
                global.data.db.updateMutationStatus(old.id, Mutation.Status.unknown);
            });
        }
    }

    void opCall(CleanupTempDirs data) {
        global.data.autoCleanup.cleanup;
    }

    void opCall(ref CheckMutantsLeft data) {
        auto mutant = spinSqlQuery!(() {
            return global.data.db.nextMutation(global.data.mutKind);
        });

        if (mutant.st == NextMutationEntry.Status.done) {
            logger.info("Done! All mutants are tested").collectException;
            data.allMutantsTested = true;
        }
    }

    void opCall(ref PreCompileSut data) {
        logger.info("Preparing for mutation testing by checking that the program and tests compile without any errors (no mutants injected)")
            .collectException;

        try {
            import std.process : execute;

            const comp_res = execute(
                    global.data.conf.mutationCompile.program
                    ~ global.data.conf.mutationCompile.arguments);

            if (comp_res.status != 0) {
                data.compilationError = true;
                logger.info(comp_res.output);
                logger.error("Compiler command failed: ", comp_res.status);
            }
        } catch (Exception e) {
            // unable to for example execute the compiler
            logger.error(e.msg).collectException;
        }
    }

    void opCall(ref MeasureTestSuite data) {
        if (global.data.conf.mutationTesterRuntime.isNull) {
            logger.info("Measuring the time to run the tests: ",
                    global.data.conf.mutationTester).collectException;
            auto tester = measureTesterDuration(global.data.conf.mutationTester);
            if (tester.status == ExitStatusType.Ok) {
                // The sampling of the test suite become too unreliable when the timeout is <1s.
                // This is a quick and dirty fix.
                // A proper fix requires an update of the sampler in runTester.
                auto t = tester.runtime < 1.dur!"seconds" ? 1.dur!"seconds" : tester.runtime;
                logger.info("Tester measured to: ", t).collectException;
                global.prog_wd = ProgressivWatchdog(t);
            } else {
                data.unreliableTestSuite = true;
                logger.error(
                        "Test suite is unreliable. It must return exit status '0' when running with unmodified mutants")
                    .collectException;
            }
        } else {
            global.prog_wd = ProgressivWatchdog(global.data.conf.mutationTesterRuntime.get);
        }
    }

    void opCall(PreMutationTest) {
        global.mut_driver = mutationDriverFactory(global.data, global.prog_wd.timeout);
    }

    void opCall(ref MutationTest data) {
        if (global.mut_driver.isRunning) {
            global.mut_driver.execute();
        } else if (global.mut_driver.stopBecauseError) {
            data.mutationError = true;
        } else if (global.mut_driver.stopMutationTesting) {
            data.allMutantsTested = true;
        } else {
            data.next = true;
        }
    }

    void opCall(ref CheckTimeout data) {
        auto entry = spinSqlQuery!(() {
            return global.data.db.timeoutMutants(global.data.mutKind);
        });

        try {
            if (!global.data.conf.mutationTesterRuntime.isNull) {
                // the user have supplied a timeout thus ignore this algorithm
                // for increasing the timeout
                data.timeoutUnchanged = true;
            } else if (entry.count == 0) {
                data.timeoutUnchanged = true;
            } else if (entry.count == global.last_timeout_mutant_count) {
                // no change between current pool of timeout mutants and the previous
                data.timeoutUnchanged = true;
            } else if (entry.count < global.last_timeout_mutant_count) {
                data.next = true;
                logger.info("Mutants with the status timeout: ", entry.count);
            }

            global.last_timeout_mutant_count = entry.count;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(IncrWatchdog data) {
        global.prog_wd.incrTimeout;
        logger.info("Increasing timeout to: ", global.prog_wd.timeout).collectException;
    }

    void opCall(ref ResetTimeout data) {
        try {
            global.data.db.resetMutant(global.data.mutKind,
                    Mutation.Status.timeout, Mutation.Status.unknown);
            data.next = true;
        } catch (Exception e) {
            // database is locked
            logger.warning(e.msg).collectException;
        }
    }
}

private:

import dextool.plugin.mutate.backend.test_mutant.interface_ : TestCaseReport;
import dextool.plugin.mutate.backend.type : TestCase;
import dextool.set;

/// Run an external program that analyze the output from the test suite for test cases that failed.
bool externalProgram(string[] cmd, TestCaseReport report) nothrow {
    import std.algorithm : copy, splitter, filter, map;
    import std.ascii : newline;
    import std.process : execute;
    import std.string : strip, startsWith;
    import dextool.plugin.mutate.backend.type : TestCase;

    immutable passed = "passed:";
    immutable failed = "failed:";
    immutable unstable = "unstable:";

    try {
        // [test_case_cmd, stdout_, stderr_]
        auto p = execute(cmd);
        if (p.status == 0) {
            foreach (l; p.output.splitter(newline).map!(a => a.strip)
                    .filter!(a => a.length != 0)) {
                if (l.startsWith(passed))
                    report.reportFound(TestCase(l[passed.length .. $].strip));
                else if (l.startsWith(failed))
                    report.reportFailed(TestCase(l[failed.length .. $].strip));
                else if (l.startsWith(unstable))
                    report.reportUnstable(TestCase(l[unstable.length .. $].strip));
            }
            return true;
        } else {
            logger.warning(p.output);
            logger.warning("Failed to analyze the test case output");
            return false;
        }
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    return false;
}

/** Analyze the output from the test suite with one of the builtin analyzers.
 *
 * trusted: because the paths to the File object are created by this program
 * and can thus not lead to memory related problems.
 */
bool builtin(AbsolutePath reldir, string[] analyze_files,
        const(TestCaseAnalyzeBuiltin)[] tc_analyze_builtin, TestCaseReport app) @trusted nothrow {
    import std.stdio : File;
    import dextool.plugin.mutate.backend.test_mutant.ctest_post_analyze;
    import dextool.plugin.mutate.backend.test_mutant.gtest_post_analyze;
    import dextool.plugin.mutate.backend.test_mutant.makefile_post_analyze;

    foreach (f; analyze_files) {
        auto gtest = GtestParser(reldir);
        CtestParser ctest;
        MakefileParser makefile;

        File* fin;
        try {
            fin = new File(f);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            return false;
        }

        scope (exit)
            () {
            try {
                fin.close;
                destroy(fin);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }();

        // an invalid UTF-8 char shall only result in the rest of the file being skipped
        try {
            foreach (l; fin.byLine) {
                // this is a magic number that felt good. Why would there be a line in a test case log that is longer than this?
                immutable magic_nr = 2048;
                if (l.length > magic_nr) {
                    // The byLine split may fail and thus result in one huge line.
                    // The result of this is that regex's that use backtracking become really slow.
                    // By skipping these lines dextool at list doesn't hang.
                    logger.warningf("Line in test case log is too long to analyze (%s > %s). Skipping...",
                            l.length, magic_nr);
                    continue;
                }

                foreach (const p; tc_analyze_builtin) {
                    final switch (p) {
                    case TestCaseAnalyzeBuiltin.gtest:
                        gtest.process(l, app);
                        break;
                    case TestCaseAnalyzeBuiltin.ctest:
                        ctest.process(l, app);
                        break;
                    case TestCaseAnalyzeBuiltin.makefile:
                        makefile.process(l, app);
                        break;
                    }
                }
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    return true;
}

/// Returns: path to a tmp directory or null on failure.
string createTmpDir(long id) nothrow {
    import std.random : uniform;
    import std.format : format;
    import std.file : mkdir, exists;

    string test_tmp_output;

    // try 5 times or bailout
    foreach (const _; 0 .. 5) {
        try {
            auto tmp = format("dextool_tmp_id_%s_%s", id, uniform!ulong);
            mkdir(tmp);
            test_tmp_output = AbsolutePath(FileName(tmp));
            break;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    if (test_tmp_output.length == 0) {
        logger.warning("Unable to create a temporary directory to store stdout/stderr in")
            .collectException;
    }

    return test_tmp_output;
}

/// Reset all alive mutants.
void resetAliveMutants(ref Database db) @safe nothrow {
    import std.traits : EnumMembers;

    // there is no use in trying to limit the mutants to reset to those that
    // are part of "this" execution because new test cases can only mean one
    // thing: re-test all alive mutants.

    spinSqlQuery!(() {
        db.resetMutant([EnumMembers!(Mutation.Kind)], Mutation.Status.alive,
            Mutation.Status.unknown);
    });
}

/** Compare the old test cases with those that have been found this run.
 *
 * TODO: the side effect that this function print to the console is NOT good.
 */
bool hasNewTestCases(ref Set!string old_tcs, ref Set!string found_tcs) @safe nothrow {
    bool rval;

    auto new_tcs = found_tcs.setDifference(old_tcs);
    foreach (tc; new_tcs.byKey) {
        logger.info(!rval, "Found new test case(s):").collectException;
        logger.infof("%s", tc).collectException;
        rval = true;
    }

    return rval;
}

/** Compare old and new test cases to print those that have been removed.
 */
void printDroppedTestCases(ref Set!string old_tcs, ref Set!string changed_tcs) @safe nothrow {
    auto diff = old_tcs.setDifference(changed_tcs);
    auto removed = diff.setToList!string;

    logger.info(removed.length != 0, "Detected test cases that has been removed:").collectException;
    foreach (tc; removed) {
        logger.infof("%s", tc).collectException;
    }
}

/// Returns: true if all tests cases have unique identifiers
void warnIfConflictingTestCaseIdentifiers(TestCase[] found_tcs) @safe nothrow {
    Set!TestCase checked;
    bool conflict;

    foreach (tc; found_tcs) {
        if (checked.contains(tc)) {
            logger.info(!conflict,
                    "Found test cases that do not have global, unique identifiers")
                .collectException;
            logger.info(!conflict,
                    "This make the report of test cases that has killed zero mutants unreliable")
                .collectException;
            logger.info("%s", tc).collectException;
            conflict = true;
        }
    }
}

/** Paths stored will be removed automatically either when manually called or goes out of scope.
 */
class AutoCleanup {
    private string[] remove_dirs;

    void add(AbsolutePath p) @safe nothrow {
        remove_dirs ~= cast(string) p;
    }

    // trusted: the paths are forced to be valid paths.
    void cleanup() @trusted nothrow {
        import std.algorithm : filter;
        import std.array : array;
        import std.file : rmdirRecurse, exists;

        foreach (ref p; remove_dirs.filter!(a => a.length != 0)) {
            try {
                if (exists(p))
                    rmdirRecurse(p);
                if (!exists(p))
                    p = null;
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }

        remove_dirs = remove_dirs.filter!(a => a.length != 0).array;
    }
}
