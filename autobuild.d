// Written in the D programming language.
/**
Date: 2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module autobuild;

import std.path : asAbsolutePath, asNormalizedPath;
import std.typecons : Flag;

import scriptlike;
import utils;

Flag!"SignalInterrupt" signalInterrupt;
Flag!"TestsPassed" signalExitStatus;

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

void playSound(Flag!"Positive" positive) {
    Args a;
    a ~= "mplayer";
    if (positive)
        a ~= "/usr/share/sounds/KDE-Sys-App-Positive.ogg";
    else
        a ~= "/usr/share/sounds/KDE-Sys-App-Negative.ogg";

    tryRunCollect(a.data);
}

bool sanityCheck() {
    if (!existsAsFile("dub.sdl")) {
        writeln("Missing dub.sdl");
        return false;
    }

    return true;
}

void setup() {
    //echoOn;

    if (!existsAsDir("build")) {
        tryRemove("build");
        mkdir("build");
    }

    import core.stdc.signal;

    signal(SIGINT, &handleSIGINT);
}

extern (C) void handleSIGINT(int sig) nothrow @nogc @system {
    .signalInterrupt = Yes.SignalInterrupt;
}

void cleanup() {
    printStatus(Status.Run, "Cleanup");
    scope (failure)
        printStatus(Status.Fail, "Cleanup");

    // dfmt off
    chain(
          dirEntries(".", "trace.*", SpanMode.shallow),
          dirEntries(".", "*.lst", SpanMode.shallow)
          )
        .map!(a => Path(a))
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
        Ut_cov,
        Debug_build,
        Debug_test,
        Test_passed,
        Test_failed,
        Doc_check_counter,
        Doc_build,
        Slocs,
        AudioStatus,
        ExitOrRestart,
        Exit
    }

    State st;
    Path[] inotify_paths;

    // Signals used to determine next state
    Flag!"UtTestPassed" flagUtTestPassed;
    Flag!"CompileError" flagCompileError;
    Flag!"TotalTestPassed" flagTotalTestPassed;
    uint docCount;

    alias ErrorMsg = Tuple!(Path, "fname", string, "msg");
    ErrorMsg[] testErrorLog;

    void run(Path[] inotify_paths, Flag!"Travis" travis) {
        this.inotify_paths = inotify_paths;

        while (!signalInterrupt) {
            debug {
                writeln("State ", st.to!string);
            }

            GenerateFsmAction(this, st);

            updateTotalTestStatus();

            st = Fsm.next(st, docCount, flagUtTestPassed, flagCompileError,
                    flagTotalTestPassed, travis);
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

    static State next(State st, uint docCount, Flag!"UtTestPassed" flagUtTestPassed,
            Flag!"CompileError" flagCompileError,
            Flag!"TotalTestPassed" flagTotalTestPassed, Flag!"Travis" travis) {
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
            break;
        case State.Ut_run:
            next_ = State.ExitOrRestart;
            if (flagUtTestPassed)
                next_ = State.Ut_cov;
            break;
        case State.Ut_cov:
            next_ = State.Debug_build;
            break;
        case State.Debug_build:
            next_ = State.Debug_test;
            if (flagCompileError)
                next_ = State.ExitOrRestart;
            break;
        case State.Debug_test:
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
            if (docCount >= 10)
                next_ = State.Doc_build;
            break;
        case State.Doc_build:
            next_ = State.Slocs;
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
        flagCompileError = Flag!"CompileError".no;
        flagUtTestPassed = Flag!"UtTestPassed".no;
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
        printStatus(Status.Run, "Compile and run unittest");

        Args a;
        a ~= thisExePath.dirName ~ "build.sh";
        a ~= "run";
        a ~= ["-c", "unittest"];
        a ~= ["-b", "unittest-cov"];
        //a ~= ["--", "-d"];

        auto r = tryRunCollect(thisExePath.dirName, a.data);
        flagUtTestPassed = r.status == 0 ? Yes.UtTestPassed : No.UtTestPassed;

        if (!flagUtTestPassed) {
            writeln(r.output);
        }

        printExitStatus(r.status, "Compile and run unittest");
    }

    void stateUt_cov() {
        //CHECK_STATUS_RVAL=0
        //for F in $(find . -iname "*.lst"|grep -v 'dub-packages'); do
        //    tail -n1 "$F"| grep -q "100% cov"
        //    if [[ $? -ne 0 ]]; then
        //        echo -e "${C_RED}Warning${C_NONE} missing coverage in ${C_YELLOW}${F}${C_NONE}"
        //        CHECK_STATUS_RVAL=1
        //    fi
        //done
        //
        //MSG="Coverage stat of unittests is"
        //if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        //    echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
        //else
        //    echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
        //fi
    }

    void stateDebug_build() {
        printStatus(Status.Run, "Debug build with debug symbols");

        Args a;
        a ~= thisExePath.dirName ~ "build.sh";
        a ~= "build";
        a ~= ["-c", "debug"];

        auto r = tryRunCollect(thisExePath.dirName, a.data);

        if (r.status == 0) {
            flagCompileError = No.CompileError;
        } else {
            flagCompileError = Yes.CompileError;
            writeln(r.output);
        }

        printExitStatus(r.status, "Debug build with debug symbols");
    }

    void stateDebug_test() {
        static void consoleToFile(Path fname, string console) {
            writeln("console log written to -> ", fname);

            auto f = File(fname.toString, "w");
            f.write(console);
        }

        void runTest(string name) {
            Args a;
            a ~= "./" ~ name;

            auto test_dir = thisExePath.dirName ~ "test";

            echoOn;
            scope (exit)
                echoOff;
            auto r = tryRunCollect(test_dir, a.data);

            auto logfile = test_dir ~ name ~ Ext(".log");
            consoleToFile(logfile, r.output);

            if (r.status != 0) {
                testErrorLog ~= ErrorMsg(logfile, name);
            }
        }

        printStatus(Status.Run, "Test of code generation");
        // dfmt off
        only(
             "external_tests.sh"
            )
            .each!(a => runTest(a));
        // dfmt on
    }

    void stateTest_passed() {
        docCount++;
        printStatus(Status.Ok, "Test of code generation");
    }

    void stateTest_failed() {
        testErrorLog.each!(a => printStatus(Status.Fail, a.msg, ", log at ", a.fname));
        printStatus(Status.Fail, "Test of code generation");
    }

    void stateDoc_check_counter() {
    }

    void stateDoc_build() {
        printStatus(Status.Run, "Generate Documenation");
        scope (exit)
            printStatus(Status.Ok, "Generate Documenation");

        docCount = 0;

        Args a;
        a ~= thisExePath.dirName ~ "build.sh";
        a ~= "build";
        a ~= ["-c", "debug"];
        a ~= ["-b", "docs"];

        tryRun(thisExePath.dirName, a.data);
    }

    void stateSlocs() {
        printStatus(Status.Run, "Code statistics");
        scope (exit)
            printStatus(Status.Ok, "Code statistics");

        // dfmt off
        auto src_paths = only(
                              "clang/*.d",
                              "dsrcgen/source/dsrcgen/*",
                              "plugin",
                              "source"
                             )
            .map!(a => thisExePath.dirName ~ a)
            .map!(a => a.toString)
            .array;
        // dfmt on

        Args a;
        a ~= "dscanner";
        a ~= "--sloc";
        a ~= src_paths;

        auto r = tryRunCollect(thisExePath.dirName, a.data);
        if (r.status == 0) {
            writeln(r.output);
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
    chdir(thisExePath.dirName);
    scope (exit)
        cleanup();

    if (!sanityCheck) {
        writeln("error: Sanity check failed");
        return 1;
    }

    import std.getopt;

    bool run_and_exit;
    getopt(args, "run_and_exit", &run_and_exit);

    setup();

    // dfmt off
    auto inotify_paths = only(
                              "source",
                              "plugin",
                              "clang",
                              "libclang",
                              "dub.sdl",
                              "dsrcgen/source",
                              "test/testdata",
                              "unit-threaded",
                              "test/cstub_tests.d",
                              "test/cpp_tests.d",
                              "test/external_main.d",
                              "test/utils.d"
        )
        .map!(a => thisExePath.dirName ~ a)
        .array;
    // dfmt on

    import std.stdio;

    (Fsm()).run(inotify_paths, run_and_exit ? Yes.Travis : No.Travis);

    return signalExitStatus ? 0 : -1;
}
