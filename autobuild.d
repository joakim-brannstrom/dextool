// Written in the D programming language.
/**
Date: 2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module autobuild;

import std.path : asAbsolutePath, asNormalizedPath;

import scriptlike;
import utils;

Flag!"SignalInterrupt" signalInterrupt;

void echoOn() {
    .scriptlikeEcho = true;
}

void echoOff() {
    .scriptlikeEcho = false;
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
    print(Color.green, "[ RUN ] Cleanup");
    scope (failure)
        print(Color.red, "[ FAIL] cleanup");

    // dfmt off
    chain(
          dirEntries(".", "trace.*", SpanMode.shallow),
          dirEntries(".", "*.lst", SpanMode.shallow)
          )
        .map!(a => Path(a))
        //.tee!(a => writeln("rm ", a))
        .each!(a => tryRemove(a));
    // dfmt on

    print(Color.green, "[  OK ] Cleanup");
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

                         },
                typeof(fsm).stringof, TEnum.stringof, e, e));
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
        Release_build,
        Release_test,
        Test_passed,
        Doc_check_counter,
        Doc_build,
        Slocs,
        AudioStatus
    }

    State st;
    Path[] inotify_paths;

    // Signals used to determine next state
    Flag!"UtTestPassed" flagUtTestPassed;
    Flag!"TestPassed" flagTestPassed;
    Flag!"CompileError" flagCompileError;
    uint docCount;

    void run(Path[] inotify_paths) {
        this.inotify_paths = inotify_paths;

        while (!signalInterrupt) {
            writeln("State ", st.to!string);

            GenerateFsmAction(this, st);

            st = Fsm.next(st, docCount, flagUtTestPassed, flagCompileError, flagTestPassed);
        }
    }

    static State next(State st, uint docCount,
        Flag!"UtTestPassed" flagUtTestPassed,
        Flag!"CompileError" flagCompileError, Flag!"TestPassed" flagTestPassed) {
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
            next_ = State.AudioStatus;
            if (flagUtTestPassed)
                next_ = State.Ut_cov;
            break;
        case State.Ut_cov:
            next_ = State.Release_build;
            break;
        case State.Release_build:
            next_ = State.Release_test;
            if (flagCompileError)
                next_ = State.AudioStatus;
            break;
        case State.Release_test:
            next_ = State.AudioStatus;
            if (flagTestPassed)
                next_ = State.Test_passed;
            break;
        case State.Test_passed:
            next_ = State.Doc_check_counter;
            break;
        case State.Doc_check_counter:
            next_ = State.AudioStatus;
            if (docCount >= 10)
                next_ = State.Doc_build;
            break;
        case State.Doc_build:
            next_ = State.Slocs;
            break;
        case State.Slocs:
            next_ = State.AudioStatus;
            break;
        }

        return next_;
    }

    static void printStatus(int status, string msg) {
        switch (status) {
        case 0:
            print(Color.green, " === " ~ msg ~ " OK ===");
            break;
        default:
            print(Color.red, " === " ~ msg ~ " ERROR ===");
        }
    }

    void stateInit() {
        // force rebuild of doc and show code stat
        docCount = 10;
    }

    void stateAudioStatus() {
        if (!flagCompileError && flagUtTestPassed && flagTestPassed)
            playSound(Yes.Positive);
        else
            playSound(No.Positive);
    }

    void stateReset() {
        flagCompileError = Flag!"CompileError".no;
        flagUtTestPassed = Flag!"UtTestPassed".no;
        flagTestPassed = Flag!"TestPassed".no;
    }

    void stateStart() {
    }

    void stateWait() {
        print(Color.yellow, "================================");

        Args a;
        a ~= "inotifywait";
        a ~= "-q";
        a ~= "-r";
        a ~= ["-e", "modify"];
        a ~= ["-e", "attrib"];
        a ~= ["-e", "create"];
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
            print(Color.red, "Error: ", r.output);
            writeln("sleeping ", SLEEP, "s");
            Thread.sleep(dur!("seconds")(SLEEP));
        }
    }

    void stateUt_run() {
        Args a;
        a ~= thisExePath.dirName ~ "build.sh";
        a ~= "run";
        a ~= ["-c", "unittest"];
        a ~= ["-b", "unittest-cov"];

        auto r = tryRunCollect(thisExePath.dirName, a.data);
        flagUtTestPassed = r.status == 0 ? Yes.UtTestPassed : No.UtTestPassed;

        if (!flagTestPassed) {
            writeln(r.output);
        }
        printStatus(r.status, "Compile and run unittest");
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

    void stateRelease_build() {
        Args a;
        a ~= thisExePath.dirName ~ "build.sh";
        a ~= "build";
        a ~= ["-c", "debug"];

        auto status = tryRun(thisExePath.dirName, a.data);

        printStatus(status, "Release build with debug symbols");
        flagCompileError = status == 0 ? No.CompileError : Yes.CompileError;
    }

    void stateRelease_test() {
        void runTest(string name) {
            // FSM exception: no use running more tests when one has failed
            if (flagTestPassed) {
                return;
            }

            Args a;
            a ~= "./" ~ name;
            a ~= buildNormalizedPathFixed(thisExePath.dirName.toString, "build", "dextool-debug");

            auto test_dir = thisExePath.dirName ~ "test";

            echoOn;
            scope (exit)
                echoOff;
            auto r = tryRunCollect(test_dir, a.data);
            flagTestPassed = r.status == 0 ? Yes.TestPassed : No.TestPassed;

            if (!flagTestPassed) {
                writeln(r.output);
            }
        }

        // dfmt off
        only(
             "cstub_tests.sh",
             "cpp_tests.sh"
             )
            .each!(a => runTest(a));
        // dfmt on
    }

    void stateTest_passed() {
        docCount++;
    }

    void stateDoc_check_counter() {
    }

    void stateDoc_build() {
        docCount = 0;

        Args a;
        a ~= thisExePath.dirName ~ "build.sh";
        a ~= "build";
        a ~= ["-c", "debug"];
        a ~= ["-b", "docs"];

        auto status = tryRun(thisExePath.dirName, a.data);
        if (status == 0)
            writeln("firefox ", thisExePath.dirName ~ "docs");
        printStatus(status, "Generate Documenation");
    }

    void stateSlocs() {
        // dfmt off
        auto src_paths = only(
                              "clang/*.d",
                              "dsrcgen/source/dsrcgen/*",
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
}

int main(string[] args) {
    chdir(thisExePath.dirName);
    scope (exit)
        cleanup();

    if (!sanityCheck) {
        writeln("error: Sanity check failed");
        return 1;
    }

    setup();

    // dfmt off
    auto inotify_paths = only(
                              "source",
                              "clang",
                              "libclang",
                              "dub.sdl",
                              "dsrcgen/source",
                              "test/testdata",
                              "unit-threaded",
                              "test/cstub_tests.d",
                              "test/cpp_tests.d"
        )
        .map!(a => thisExePath.dirName ~ a)
        .array;
    // dfmt on

    import std.stdio;

    writeln("Watching the following paths for changes:");
    inotify_paths.each!writeln;

    (Fsm()).run(inotify_paths);

    return 0;
}
