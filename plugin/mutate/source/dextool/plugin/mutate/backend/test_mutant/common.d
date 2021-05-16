/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Common functionality used both by source and schemata testing of a mutant.
*/
module dextool.plugin.mutate.backend.test_mutant.common;

import logger = std.experimental.logger;
import std.algorithm : map, filter;
import std.array : empty, array;
import std.datetime : Duration, dur;
import std.exception : collectException;
import std.path : buildPath;
import std.typecons : Flag, No;

import blob_model : Blob;
import my.named_type;
import proc : DrainElement;
import sumtype;

import dextool.plugin.mutate.backend.database : MutationId;
import dextool.plugin.mutate.backend.interface_;
import dextool.plugin.mutate.backend.test_mutant.test_case_analyze : GatherTestCase;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand;
import dextool.type : AbsolutePath, Path;

public import dextool.plugin.mutate.backend.type : Mutation, TestCase,
    ExitStatus, MutantTimeProfile;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

/// The result of running the test suite on one mutant.
struct MutationTestResult {
    import std.datetime : Duration;
    import dextool.plugin.mutate.backend.database : MutationStatusId, MutationId;
    import dextool.plugin.mutate.backend.type : Mutation, TestCase, ExitStatus;

    MutationId mutId;
    MutationStatusId id;
    Mutation.Status status;
    MutantTimeProfile profile;
    TestCase[] testCases;
    ExitStatus exitStatus;
}

/** Analyze stdout/stderr output from a test suite for test cases that failed
 * (killed) a mutant, which test cases that exists and if any of them are
 * unstable.
 */
struct TestCaseAnalyzer {
    private {
        ShellCommand[] externalAnalysers;
        TestCaseAnalyzeBuiltin[] builtins;
        AutoCleanup cleanup;
    }

    static struct Success {
        TestCase[] failed;
        TestCase[] found;
    }

    static struct Unstable {
        TestCase[] unstable;
        TestCase[] found;
    }

    static struct Failed {
    }

    alias Result = SumType!(Success, Unstable, Failed);

    this(TestCaseAnalyzeBuiltin[] builtins, ShellCommand[] externalAnalyzers, AutoCleanup cleanup) {
        this.externalAnalysers = externalAnalyzers;
        this.builtins = builtins;
        this.cleanup = cleanup;
    }

    Result analyze(DrainElement[] data, Flag!"allFound" allFound = No.allFound) {
        import dextool.plugin.mutate.backend.test_mutant.test_case_analyze : GatherTestCase;

        GatherTestCase gather;

        // the post processer must succeeed for the data to be stored. It is
        // considered a major error that may corrupt existing data if it fails.
        bool success = true;

        if (!externalAnalysers.empty) {
            foreach (cmd; externalAnalysers) {
                success = success && externalProgram(cmd, data, gather, cleanup);
            }
        }
        if (!builtins.empty) {
            builtin(data, builtins, gather);
        }

        if (!gather.unstable.empty) {
            return Result(Unstable(gather.unstableAsArray, allFound ? gather.foundAsArray : null));
        }

        if (success) {
            return Result(Success(gather.failedAsArray, allFound ? gather.foundAsArray : null));
        }

        return Result(Failed.init);
    }

    /// Returns: true if there are no analyzers setup.
    bool empty() @safe pure nothrow const @nogc {
        return externalAnalysers.empty && builtins.empty;
    }
}

/** Analyze the output from the test suite with one of the builtin analyzers.
 */
void builtin(DrainElement[] output,
        const(TestCaseAnalyzeBuiltin)[] tc_analyze_builtin, ref GatherTestCase app) @safe nothrow {
    import dextool.plugin.mutate.backend.test_mutant.ctest_post_analyze;
    import dextool.plugin.mutate.backend.test_mutant.gtest_post_analyze;
    import dextool.plugin.mutate.backend.test_mutant.makefile_post_analyze;

    GtestParser gtest;
    CtestParser ctest;
    MakefileParser makefile;

    void analyzeLine(const(char)[] line) {
        // this is a magic number that felt good. Why would there be a line in a test case log that is longer than this?
        immutable magic_nr = 2048;
        if (line.length > magic_nr) {
            // The byLine split may fail and thus result in one huge line.
            // The result of this is that regex's that use backtracking become really slow.
            // By skipping these lines dextool at list doesn't hang.
            logger.warningf("Line in test case log is too long to analyze (%s > %s). Skipping...",
                    line.length, magic_nr);
            return;
        }

        foreach (const p; tc_analyze_builtin) {
            final switch (p) {
            case TestCaseAnalyzeBuiltin.gtest:
                gtest.process(line, app);
                break;
            case TestCaseAnalyzeBuiltin.ctest:
                ctest.process(line, app);
                break;
            case TestCaseAnalyzeBuiltin.makefile:
                makefile.process(line, app);
                break;
            }
        }
    }

    foreach (l; LineRange(output)) {
        try {
            analyzeLine(l);
        } catch (Exception e) {
            logger.warning("A error encountered when trying to analyze the output from the test suite. Ignoring the offending line.")
                .collectException;
            logger.warning(e.msg).collectException;
        }
    }

    foreach (const p; tc_analyze_builtin) {
        final switch (p) {
        case TestCaseAnalyzeBuiltin.gtest:
            gtest.finalize(app);
            break;
        case TestCaseAnalyzeBuiltin.ctest:
            break;
        case TestCaseAnalyzeBuiltin.makefile:
            break;
        }
    }
}

struct LineRange {
    DrainElement[] elems;
    const(char)[] buf;
    const(char)[] line;

    const(char)[] front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return line;
    }

    void popFront() @safe nothrow {
        assert(!empty, "Can't pop front of an empty range");
        import std.algorithm : countUntil;

        static auto nextLine(ref const(char)[] buf) @safe nothrow {
            const(char)[] line;

            try {
                const idx = buf.countUntil('\n');
                if (idx != -1) {
                    line = buf[0 .. idx];
                    if (idx < buf.length) {
                        buf = buf[idx + 1 .. $];
                    } else {
                        buf = null;
                    }
                }
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
                logger.warning("Unable to parse the buffered data for a newline. Ignoring the rest.")
                    .collectException;
                buf = null;
            }

            return line;
        }

        line = null;
        while (!elems.empty && line.empty) {
            try {
                auto tmp = elems[0].byUTF8.array;
                buf ~= tmp;
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
                logger.warning(
                        "A error encountered when trying to parse the output as UTF-8. Ignoring the offending data.")
                    .collectException;
            }
            elems = elems[1 .. $];
            line = nextLine(buf);
        }

        const s = buf.length;
        // there are data in the buffer that may contain lines
        if (elems.empty && !buf.empty && line.empty) {
            line = nextLine(buf);
        }

        // the last data in the buffer. This is a special case if an
        // application write data but do not end the last block of data with a
        // newline.
        // `s == buf.length` handles the case wherein there is an empty line.
        if (elems.empty && !buf.empty && line.empty && (s == buf.length)) {
            line = buf;
            buf = null;
        }
    }

    bool empty() @safe pure nothrow const @nogc {
        return elems.empty && buf.empty && line.empty;
    }
}

@("shall end the parsing of DrainElements even if the last is missing a newline")
unittest {
    import std.algorithm : copy;
    import std.array : appender;

    auto app = appender!(DrainElement[])();
    ["foo", "bar\n", "smurf"].map!(a => DrainElement(DrainElement.Type.stdout,
            cast(const(ubyte)[]) a)).copy(app);

    auto r = LineRange(app.data);

    r.empty.shouldBeFalse;
    r.popFront;
    r.front.shouldEqual("foobar");

    r.empty.shouldBeFalse;
    r.popFront;
    r.front.shouldEqual("smurf");

    r.empty.shouldBeFalse;
    r.popFront;
    r.empty.shouldBeTrue;
}

/** Run an external program that analyze the output from the test suite for
 * test cases that failed.
 *
 * Params:
 * cmd = user analyze command to execute on the output
 * output = output from the test command to be passed on to the analyze command
 * report = the result is stored in the report
 *
 * Returns: True if it successfully analyzed the output
 */
bool externalProgram(ShellCommand cmd, DrainElement[] output,
        ref GatherTestCase report, AutoCleanup cleanup) @safe nothrow {
    import std.datetime : dur;
    import std.algorithm : copy;
    import std.ascii : newline;
    import std.string : strip, startsWith;
    import proc;

    immutable passed = "passed:";
    immutable failed = "failed:";
    immutable unstable = "unstable:";

    auto tmpdir = createTmpDir();
    if (tmpdir.empty) {
        return false;
    }

    ShellCommand writeOutput(ShellCommand cmd) @safe {
        import std.stdio : File;

        const stdoutPath = buildPath(tmpdir, "stdout.log");
        const stderrPath = buildPath(tmpdir, "stderr.log");
        auto stdout = File(stdoutPath, "w");
        auto stderr = File(stderrPath, "w");

        foreach (a; output) {
            final switch (a.type) {
            case DrainElement.Type.stdout:
                stdout.rawWrite(a.data);
                break;
            case DrainElement.Type.stderr:
                stderr.rawWrite(a.data);
                break;
            }
        }

        cmd.value ~= [stdoutPath, stderrPath];
        return cmd;
    }

    try {
        cleanup.add(tmpdir.Path.AbsolutePath);
        cmd = writeOutput(cmd);
        auto p = pipeProcess(cmd.value).sandbox.rcKill;
        foreach (l; p.process.drainByLineCopy().map!(a => a.strip)
                .filter!(a => !a.empty)) {
            if (l.startsWith(passed))
                report.reportFound(TestCase(l[passed.length .. $].strip.idup));
            else if (l.startsWith(failed))
                report.reportFailed(TestCase(l[failed.length .. $].strip.idup));
            else if (l.startsWith(unstable))
                report.reportUnstable(TestCase(l[unstable.length .. $].strip.idup));
        }

        if (p.wait == 0) {
            return true;
        }

        logger.warningf("Failed to analyze the test case output with command '%-(%s %)'", cmd);
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    return false;
}

/// Returns: path to a tmp directory or null on failure.
string createTmpDir() @safe nothrow {
    import std.random : uniform;
    import std.format : format;
    import std.file : mkdir;

    string test_tmp_output;

    // try 5 times or bailout
    foreach (const _; 0 .. 5) {
        try {
            auto tmp = format!"dextool_tmp_id_%s"(uniform!ulong);
            mkdir(tmp);
            test_tmp_output = AbsolutePath(Path(tmp));
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

/** Paths stored will be removed automatically either when manually called or
 * goes out of scope.
 */
class AutoCleanup {
    private string[] remove_dirs;

    void add(AbsolutePath p) @safe nothrow {
        remove_dirs ~= cast(string) p;
    }

    // trusted: the paths are forced to be valid paths.
    void cleanup() @trusted nothrow {
        import std.file : rmdirRecurse, exists;

        foreach (ref p; remove_dirs.filter!(a => !a.empty)) {
            try {
                if (exists(p))
                    rmdirRecurse(p);
                if (!exists(p))
                    p = null;
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }

        remove_dirs = remove_dirs.filter!(a => !a.empty).array;
    }
}

alias CompileResult = SumType!(Mutation.Status, bool);
alias PrintCompileOnFailure = NamedType!(bool, Tag!"CompileActionOnFailure",
        bool.init, TagStringable, ImplicitConvertable);

CompileResult compile(ShellCommand cmd, Duration timeout, PrintCompileOnFailure printOnFailure) @trusted nothrow {
    import proc;
    import std.datetime : Clock;
    import std.stdio : write, writeln;

    const auto started = Clock.currTime;
    // every minute print something to indicate that the process is still
    // alive. Otherwise e.g. Jenkins may determine that it is dead.
    auto nextTick = Clock.currTime + 1.dur!"minutes";
    void tick() {
        const now = Clock.currTime;
        if (now > nextTick) {
            nextTick = now + 1.dur!"minutes";
            writeln("compiling... ", now - started);
        }
    }

    int runCompilation(bool print) {
        auto p = () {
            if (cmd.value.length == 1) {
                return pipeShell(cmd.value[0]).sandbox.timeout(timeout).rcKill;
            }
            return pipeProcess(cmd.value).sandbox.timeout(timeout).rcKill;
        }();

        ulong bytes;
        foreach (a; p.process.drain) {
            if (!a.empty && print) {
                write(a.byUTF8);
            } else if (!print) {
                tick();
            }
        }

        return p.wait;
    }

    try {
        auto exitStatus = runCompilation(false);
        if (exitStatus != 0 && printOnFailure)
            exitStatus = runCompilation(true);

        if (exitStatus != 0)
            return CompileResult(Mutation.Status.killedByCompiler);
    } catch (Exception e) {
        logger.warning("Unknown error when executing the build command").collectException;
        logger.warning(cmd.value).collectException;
        logger.warning(e.msg).collectException;
        return CompileResult(Mutation.Status.unknown);
    }

    return CompileResult(true);
}

struct TestResult {
    Mutation.Status status;
    ExitStatus exitStatus;
    DrainElement[][ShellCommand] output;
}

/** Run the test suite to verify a mutation.
 *
 * Returns: the result of testing the mutant.
 */
TestResult runTester(Args...)(ref TestRunner runner, auto ref Args args) nothrow {
    import proc;

    TestResult rval;
    try {
        auto res = runner.run(args);
        rval.output = res.output;
        rval.exitStatus = res.exitStatus;

        final switch (res.status) with (
            dextool.plugin.mutate.backend.test_mutant.test_cmd_runner.TestResult.Status) {
        case passed:
            rval.status = Mutation.Status.alive;
            break;
        case failed:
            rval.status = Mutation.Status.killed;
            break;
        case timeout:
            rval.status = Mutation.Status.timeout;
            break;
        case error:
            rval.status = Mutation.Status.unknown;
            break;
        }
    } catch (Exception e) {
        // unable to for example execute the test suite
        logger.warning(e.msg).collectException;
        rval.status = Mutation.Status.unknown;
    }

    return rval;
}

void restoreFiles(AbsolutePath[] files, FilesysIO fio) {
    foreach (a; files) {
        fio.makeOutput(a).write(fio.makeInput(a));
    }
}

/// The conditions for when to stop mutation testing.
/// Intended to be re-used by both the main FSM and the sub-FSMs.
struct TestStopCheck {
    import std.format : format;
    import std.datetime.systime : Clock, SysTime;
    import my.optional;
    import dextool.plugin.mutate.config : ConfigMutationTest;

    enum HaltReason {
        none,
        maxRuntime,
        aliveTested,
        overloaded,
    }

    private {
        typeof(ConfigMutationTest.loadBehavior) loadBehavior;
        typeof(ConfigMutationTest.loadThreshold) baseLoadThreshold;
        typeof(ConfigMutationTest.loadThreshold) loadThreshold;

        Optional!int maxAlive;

        /// Max time to run the mutation testing for.
        SysTime stopAt;
        Duration maxRuntime;

        long aliveMutants_;
    }

    this(ConfigMutationTest conf) {
        loadBehavior = conf.loadBehavior;
        loadThreshold = conf.loadThreshold;
        baseLoadThreshold = conf.loadThreshold;
        if (!conf.maxAlive.isNull)
            maxAlive = some(conf.maxAlive.get);
        stopAt = Clock.currTime + conf.maxRuntime;
        maxRuntime = conf.maxRuntime;
    }

    void incrAliveMutants() @safe pure nothrow @nogc {
        ++aliveMutants_;
    }

    long aliveMutants() @safe pure nothrow const @nogc {
        return aliveMutants_;
    }

    /// A halt conditions has occured. Mutation testing should stop.
    HaltReason isHalt() @safe nothrow {
        if (isMaxRuntime)
            return HaltReason.maxRuntime;

        if (isAliveTested)
            return HaltReason.aliveTested;

        if (loadBehavior == ConfigMutationTest.LoadBehavior.halt && load15 > baseLoadThreshold.get)
            return HaltReason.overloaded;

        return HaltReason.none;
    }

    /// The system is overloaded and the user has configured the tool to slowdown.
    bool isOverloaded() @safe nothrow const @nogc {
        if (loadBehavior == ConfigMutationTest.LoadBehavior.slowdown && load15 > loadThreshold.get)
            return true;

        return false;
    }

    bool isAliveTested() @safe pure nothrow @nogc {
        return maxAlive.hasValue && aliveMutants_ >= maxAlive.orElse(0);
    }

    bool isMaxRuntime() @safe nothrow const {
        return Clock.currTime > stopAt;
    }

    double load15() nothrow const @nogc @trusted {
        import my.libc : getloadavg;

        double[3] load;
        const nr = getloadavg(&load[0], 3);
        if (nr <= 0 || nr > load.length) {
            return 0.0;
        }
        return load[nr - 1];
    };

    /// Pause the current thread by sleeping.
    void pause() @trusted nothrow {
        import core.thread : Thread;
        import std.algorithm : max;

        const sleepFor = 30.dur!"seconds";
        logger.infof("Sleeping %s", sleepFor).collectException;
        Thread.sleep(sleepFor);

        // make it more sensitive if the system is still overloaded.
        if (load15 > loadThreshold.get)
            loadThreshold.get = max(1, baseLoadThreshold.get - 1);
        else
            loadThreshold = baseLoadThreshold;
    }

    string overloadToString() @safe const {
        return format!"Detected overload (%s > %s)"(load15, loadThreshold.get);
    }

    string maxRuntimeToString() @safe const {
        return format!"Max runtime of %s reached at %s"(maxRuntime, Clock.currTime);
    }
}

struct HashFile {
    import my.hash : Checksum64;

    Checksum64 cs;
    Path file;
}

auto hashFiles(RangeT)(RangeT files) {
    import my.hash : makeCrc64Iso, checksum;
    import my.file : existsAnd, isFile;

    return files.filter!(a => existsAnd!isFile(Path(a)))
        .map!((a) {
            auto p = AbsolutePath(a);
            auto cs = checksum!makeCrc64Iso(p);
            return HashFile(cs, Path(a));
        });
}
