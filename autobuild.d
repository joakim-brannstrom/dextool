/**
Date: 2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module autobuild;

import std.typecons : Flag, Yes, No;

import scriptlike;

Flag!"SignalInterrupt" signalInterrupt;
Flag!"TestsPassed" signalExitStatus;

bool skipStaticAnalysis = true;

void echoOn() {
    .scriptlikeEcho = true;
}

void echoOff() {
    .scriptlikeEcho = false;
}

enum Color {
    red,
    green,
    yellow,
    cancel
}

enum Status {
    Fail,
    Warn,
    Ok,
    Run
}

auto sourcePath() {
    // those that are supported by the developer of deXtool

    // dfmt off
    return only(
                "clang",
                "dextool_clang_extensions",
                "dsrcgen/source",
                "llvm_hiwrap/source",
                "plugin",
                "source",
               )
        .map!(a => thisExePath.dirName ~ a)
        .map!(a => a.toString)
        .array();
    // dfmt on
}

auto gitHEAD() {
    // Initial commit: diff against an empty tree object
    string against = "4b825dc642cb6eb9a060e54bf8d69288fbee4904";

    auto res = tryRunCollect("git rev-parse --verify HEAD");
    if (res.status == 0) {
        against = res.output;
    }

    return against;
}

auto gitChangdedFiles(string[] file_extensions) {
    import std.ascii : newline;

    Args a;
    a ~= "git";
    a ~= "diff-index";
    a ~= "--name-status";
    a ~= ["--cached", gitHEAD];

    auto res = tryRunCollect(a.data);
    if (res.status != 0) {
        writeln("error: ", res.output);
    }

    // dfmt off
    return res.output
        .splitter(newline)
        .map!(a => a.splitter.array())
        .filter!(a => a.length == 2)
        .filter!(a => a[0].among("M", "A"))
        .filter!(a => canFind(file_extensions, std.path.extension(a[1])))
        .map!(a => a[1]);
    // dfmt on
}

auto sourceAsInclude() {
    // dfmt off
    return only(
                "dsrcgen/source",
                "source",
                "clang",
                "libclang",
               )
        .map!(a => thisExePath.dirName ~ a)
        .map!(a => "-I" ~ a.toString)
        .array();
    // dfmt on
}

auto consoleStaticAnalyse(R)(R lines) {
    import std.algorithm;
    import std.string;

    // dfmt off
    auto needles = [
        "taggedalgebraic",
         "Could not resolve location of module"];

    return lines
        // remove those that contains the substrings
        .filter!((string line) => !any!(a => indexOf(line, a) != -1)(needles))
        // 15 is arbitrarily chosen
        .take(15);
    // dfmt on
}

void print(T...)(Color c, T args) {
    static immutable string[] escCodes = ["\033[31;1m", "\033[32;1m", "\033[33;1m", "\033[0;;m"];
    write(escCodes[c], args, escCodes[Color.cancel]);
}

void println(T...)(Color c, T args) {
    static immutable string[] escCodes = ["\033[31;1m", "\033[32;1m", "\033[33;1m", "\033[0;;m"];
    writeln(escCodes[c], args, escCodes[Color.cancel]);
}

void printStatus(T...)(Status s, T args) {
    Color c;
    string txt;

    final switch (s) {
    case Status.Ok:
        c = Color.green;
        txt = "[  OK ] ";
        break;
    case Status.Run:
        c = Color.yellow;
        txt = "[ RUN ] ";
        break;
    case Status.Fail:
        c = Color.red;
        txt = "[ FAIL] ";
        break;
    case Status.Warn:
        c = Color.red;
        txt = "[ WARN] ";
        break;
    }

    print(c, txt);
    writeln(args);
}

void playSound(Flag!"Positive" positive) nothrow {
    static import std.stdio;
    import std.process;

    static Pid last_pid;

    try {
        auto devnull = std.stdio.File("/dev/null", "w");

        if (last_pid !is null && last_pid.processID != 0) {
            // cleanup possible zombie process
            last_pid.wait;
        }

        auto a = ["mplayer", "-nostop-xscreensaver"];
        if (positive)
            a ~= "/usr/share/sounds/KDE-Sys-App-Positive.ogg";
        else
            a ~= "/usr/share/sounds/KDE-Sys-App-Negative.ogg";

        last_pid = spawnProcess(a, std.stdio.stdin, devnull, devnull);
    }
    catch (ProcessException ex) {
    }
    catch (Exception ex) {
    }
}

bool sanityCheck() {
    if (!existsAsFile("dub.sdl")) {
        writeln("Missing dub.sdl");
        return false;
    }

    return true;
}

void consoleToFile(Path fname, string console) {
    writeln("console log written to -> ", fname);

    auto f = File(fname.toString, "w");
    f.write(console);
}

Path cmakeDir() {
    return thisExePath.dirName ~ "build";
}

void setup() {
    //echoOn;

    if (!existsAsDir("build")) {
        tryRemove("build");
        mkdir("build");
    }

    auto r = tryRunCollect(cmakeDir, "cmake -DCMAKE_BUILD_TYPE=Debug -DBUILD_TEST=ON ..");
    writeln(r.output);

    import core.stdc.signal;

    signal(SIGINT, &handleSIGINT);
}

extern (C) void handleSIGINT(int sig) nothrow @nogc @system {
    .signalInterrupt = Yes.SignalInterrupt;
}

void cleanup(Flag!"keepCoverage" keep_cov) {
    import std.algorithm : predSwitch;

    printStatus(Status.Run, "Cleanup");
    scope (failure)
        printStatus(Status.Fail, "Cleanup");

    // dfmt off
    chain(
          dirEntries(".", "trace.*", SpanMode.shallow).map!(a => Path(a)).array(),
          keep_cov.predSwitch(Yes.keepCoverage, string[].init.map!(a => Path(a)).array(),
                              No.keepCoverage, dirEntries(".", "*.lst", SpanMode.shallow).map!(a => Path(a)).array())
         )
        .each!(a => tryRemove(a));
    // dfmt on

    printStatus(Status.Ok, "Cleanup");
}

/** Call appropriate function for for the state.
 *
 * Generate calls to functions of fsm based on st.
 *
 * Params:
 *  fsm = object with methods with prefix st_
 *  st = current state
 */
auto GenerateFsmAction(T, TEnum)(ref T fsm, TEnum st) {
    import std.traits;

    final switch (st) {
        foreach (e; EnumMembers!TEnum) {
            mixin(format(q{
                         case %s.%s.%s:
                           fsm.state%s();
                           break;

                         }, typeof(fsm).stringof, TEnum.stringof, e, e));
        }
    }
}

/// Moore FSM
/// Exceptions are clearly documented with // FSM exception: REASON
struct Fsm {
    enum State {
        Init,
        Reset,
        Wait,
        Start,
        Ut_run,
        Ut_skip,
        Debug_build,
        Integration_test,
        Test_passed,
        Test_failed,
        Doc_check_counter,
        Doc_build,
        Sloc_check_counter,
        Slocs,
        AudioStatus,
        ExitOrRestart,
        Exit
    }

    State st;
    Path[] inotify_paths;

    Flag!"utDebug" flagUtDebug;

    // Signals used to determine next state
    Flag!"UtTestPassed" flagUtTestPassed;
    Flag!"CompileError" flagCompileError;
    Flag!"TotalTestPassed" flagTotalTestPassed;
    int docCount;
    int analyzeCount;

    alias ErrorMsg = Tuple!(Path, "fname", string, "msg", string, "output");
    ErrorMsg[] testErrorLog;

    void run(Path[] inotify_paths, Flag!"Travis" travis,
            Flag!"utDebug" ut_debug, Flag!"utSkip" ut_skip) {
        this.inotify_paths = inotify_paths;
        this.flagUtDebug = ut_debug;

        while (!signalInterrupt) {
            debug {
                writeln("State ", st.to!string);
            }

            GenerateFsmAction(this, st);

            updateTotalTestStatus();

            st = Fsm.next(st, docCount, analyzeCount, flagUtTestPassed,
                    flagCompileError, flagTotalTestPassed, travis, ut_skip);
        }
    }

    void updateTotalTestStatus() {
        if (testErrorLog.length != 0) {
            flagTotalTestPassed = No.TotalTestPassed;
        } else if (flagUtTestPassed == No.UtTestPassed) {
            flagTotalTestPassed = No.TotalTestPassed;
        } else if (flagCompileError == Yes.CompileError) {
            flagTotalTestPassed = No.TotalTestPassed;
        } else {
            flagTotalTestPassed = Yes.TotalTestPassed;
        }
    }

    static State next(State st, int docCount, int analyzeCount,
            Flag!"UtTestPassed" flagUtTestPassed, Flag!"CompileError" flagCompileError,
            Flag!"TotalTestPassed" flagTotalTestPassed, Flag!"Travis" travis,
            Flag!"utSkip" ut_skip) {
        auto next_ = st;

        final switch (st) {
        case State.Init:
            next_ = State.Start;
            break;
        case State.AudioStatus:
            next_ = State.Reset;
            break;
        case State.Reset:
            next_ = State.Wait;
            break;
        case State.Wait:
            next_ = State.Start;
            break;
        case State.Start:
            next_ = State.Ut_run;
            if (ut_skip) {
                next_ = State.Ut_skip;
            }
            break;
        case State.Ut_run:
            next_ = State.ExitOrRestart;
            if (flagUtTestPassed)
                next_ = State.Integration_test;
            break;
        case State.Ut_skip:
            next_ = State.Integration_test;
            break;
        case State.Debug_build:
            next_ = State.Integration_test;
            if (flagCompileError)
                next_ = State.ExitOrRestart;
            break;
        case State.Integration_test:
            next_ = State.ExitOrRestart;
            if (flagTotalTestPassed)
                next_ = State.Test_passed;
            else
                next_ = State.Test_failed;
            break;
        case State.Test_passed:
            next_ = State.Doc_check_counter;
            break;
        case State.Test_failed:
            next_ = State.ExitOrRestart;
            break;
        case State.Doc_check_counter:
            next_ = State.ExitOrRestart;
            if (docCount >= 10 && !travis)
                next_ = State.Doc_build;
            break;
        case State.Doc_build:
            next_ = State.Sloc_check_counter;
            break;
        case State.Sloc_check_counter:
            next_ = State.ExitOrRestart;
            if (analyzeCount >= 10) {
                next_ = State.Slocs;
            }
            break;
        case State.Slocs:
            next_ = State.ExitOrRestart;
            break;
        case State.ExitOrRestart:
            next_ = State.AudioStatus;
            if (travis) {
                next_ = State.Exit;
            }
            break;
        case State.Exit:
            break;
        }

        return next_;
    }

    static void printExitStatus(T...)(int status, T args) {
        if (status == 0)
            printStatus(Status.Ok, args);
        else
            printStatus(Status.Fail, args);
    }

    void stateInit() {
        // force rebuild of doc and show code stat
        docCount = 10;
        analyzeCount = 10;

        writeln("Watching the following paths for changes:");
        inotify_paths.each!writeln;
    }

    void stateAudioStatus() {
        if (!flagCompileError && flagUtTestPassed && testErrorLog.length == 0)
            playSound(Yes.Positive);
        else
            playSound(No.Positive);
    }

    void stateReset() {
        flagCompileError = No.CompileError;
        flagUtTestPassed = No.UtTestPassed;
        testErrorLog.length = 0;
    }

    void stateStart() {
    }

    void stateWait() {
        println(Color.yellow, "================================");

        Args a;
        a ~= "inotifywait";
        a ~= "-q";
        a ~= "-r";
        a ~= ["-e", "modify"];
        a ~= ["-e", "attrib"];
        a ~= ["-e", "create"];
        a ~= ["-e", "move_self"];
        a ~= ["--format", "%w"];
        a ~= inotify_paths;

        auto r = tryRunCollect(thisExePath.dirName, a.data);

        import core.thread;

        if (signalInterrupt) {
            // do nothing, a SIGINT has been received while sleeping
        } else if (r.status == 0) {
            writeln("Change detected in ", r.output);
            // wait for editor to finish saving the file
            Thread.sleep(dur!("msecs")(500));
        } else {
            enum SLEEP = 10;
            writeln(a.data);
            printStatus(Status.Warn, "Error: ", r.output);
            writeln("sleeping ", SLEEP, "s");
            Thread.sleep(dur!("seconds")(SLEEP));
        }
    }

    void stateUt_run() {
        immutable test_header = "Compile and run unittest";
        printStatus(Status.Run, test_header);

        auto r = tryRunCollect(cmakeDir, "make check -j $(nproc)");
        flagUtTestPassed = cast(Flag!"UtTestPassed")(r.status == 0);

        if (!flagUtTestPassed || flagUtDebug) {
            consoleToFile(cmakeDir ~ "test" ~ "unittest" ~ Ext(".log"), r.output);
            writeln(r.output);
        }

        printExitStatus(r.status, test_header);
    }

    void stateUt_skip() {
        flagUtTestPassed = Yes.UtTestPassed;
    }

    void stateDebug_build() {
        printStatus(Status.Run, "Debug build");

        auto r = tryRun(cmakeDir, "make all -j $(nproc)");
        flagCompileError = cast(Flag!"CompileError")(r != 0);
        printExitStatus(r, "Debug build with debug symbols");
    }

    void stateIntegration_test() {
        immutable test_header = "Compile and run integration tests";
        printStatus(Status.Run, test_header);

        if (tryRun(cmakeDir, `make check_integration -j $(nproc)`) != 0) {
            testErrorLog ~= ErrorMsg(cmakeDir, "integration_test", "failed");
            printExitStatus(1, test_header);
            return;
        }

        printExitStatus(0, test_header);
    }

    void stateTest_passed() {
        docCount++;
        analyzeCount++;
        printStatus(Status.Ok, "Test of code generation");
    }

    void stateTest_failed() {
        // separate the log dump to the console from the list of files the logs can be found in.
        // Most common scenario is one failure.
        testErrorLog.each!((a) { writeln(a.output); });
        testErrorLog.each!((a) {
            printStatus(Status.Fail, a.msg, ", log at ", a.fname);
        });

        printStatus(Status.Fail, "Test of code generation");
    }

    void stateDoc_check_counter() {
    }

    void stateDoc_build() {
    }

    void stateSloc_check_counter() {
    }

    void stateSlocs() {
        printStatus(Status.Run, "Code statistics");
        scope (exit)
            printStatus(Status.Ok, "Code statistics");

        Args a;
        a ~= "dscanner";
        a ~= "--sloc";
        a ~= sourcePath.array();

        auto r = tryRunCollect(thisExePath.dirName, a.data);
        if (r.status == 0) {
            writeln(r.output);
        }

        analyzeCount = 0;
    }

    void stateStaticAnalyse() {
        static import std.file;

        static import std.stdio;

        static import core.stdc.stdlib;

        printStatus(Status.Run, "Static analyze");

        // dscanner hangs during analysis
        if (skipStaticAnalysis)
            return;

        string phobos_path = core.stdc.stdlib.getenv("DLANG_PHOBOS_PATH".toStringz)
            .fromStringz.idup;
        string druntime_path = core.stdc.stdlib.getenv("DLANG_DRUNTIME_PATH".toStringz)
            .fromStringz.idup;

        Args a;
        a ~= "dscanner";
        a ~= ["--config", (thisExePath.dirName ~ ".dscanner.ini").toString];
        a ~= "--styleCheck";
        a ~= "--skipTests";

        if (phobos_path.length > 0 && druntime_path.length > 0) {
            a ~= ["-I", phobos_path];
            a ~= ["-I", druntime_path];
        } else {
            println(Color.red, "Extra errors during static analyze");
            println(Color.red, "Missing env variable DLANG_PHOBOS_PATH and/or DLANG_DRUNTIME_PATH");
        }

        a ~= sourceAsInclude;
        a ~= gitChangdedFiles([".d"]);

        auto r = tryRunCollect(thisExePath.dirName, a.data);

        string reportFile = (thisExePath.dirName ~ "dscanner_report.txt").toString;
        if (r.status != 0) {
            auto lines = r.output.splitter("\n");
            const auto dscanner_count = lines.save.count;

            // console dump
            consoleStaticAnalyse(lines.save).each!writeln;

            // dump to file
            auto fout = File(reportFile, "w");
            fout.write(a.data ~ "\n" ~ r.output);

            printStatus(Status.Fail, "Static analyze failed. Found ",
                    dscanner_count, " error(s). See report ", reportFile);
        } else {
            tryRemove(reportFile);
            printStatus(Status.Ok, "Static analysis");
        }
    }

    void stateExitOrRestart() {
    }

    void stateExit() {
        if (flagTotalTestPassed) {
            .signalExitStatus = Yes.TestsPassed;
        } else {
            .signalExitStatus = No.TestsPassed;
        }
        .signalInterrupt = Yes.SignalInterrupt;
    }
}

int main(string[] args) {
    Flag!"keepCoverage" keep_cov;

    chdir(thisExePath.dirName);
    scope (exit)
        cleanup(keep_cov);

    if (!sanityCheck) {
        writeln("error: Sanity check failed");
        return 1;
    }

    import std.getopt;

    bool run_and_exit;
    bool ut_debug;
    bool ut_skip;

    // dfmt off
    auto help_info = getopt(args,
        "run_and_exit", "run the tests in one pass and exit", &run_and_exit,
        "ut_debug", "run tests in single threaded debug mode", &ut_debug,
        "ut_skip", "skip unittests to go straight to the integration tests", &ut_skip);
    // dfmt on

    if (help_info.helpWanted) {
        defaultGetoptPrinter("Usage: autobuild.sh [options]", help_info.options);
        return 0;
    }

    setup();

    // dfmt off
    auto inotify_paths = only(
                              "source",
                              "plugin",
                              "clang",
                              "dextool_clang_extensions",
                              "libclang",
                              "dub.sdl",
                              "dsrcgen/source",
                              "llvm_hiwrap",
                              "test/testdata",
                              "vendor",
                              "test/source"
        )
        .map!(a => thisExePath.dirName ~ a)
        .array;
    // dfmt on

    import std.stdio;

    (Fsm()).run(inotify_paths, cast(Flag!"Travis") run_and_exit,
            cast(Flag!"utDebug") ut_debug, cast(Flag!"utSkip") ut_skip);

    return signalExitStatus ? 0 : -1;
}
