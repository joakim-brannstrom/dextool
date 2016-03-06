// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module utils;
import scriptlike;

void echoOn() {
    .scriptlikeEcho = true;
}

void echoOff() {
    .scriptlikeEcho = false;
}

string escapePath(in Path p) {
    import scriptlike : escapeShellArg;

    return p.toRawString.dup.escapeShellArg;
}

void runAndLog(string args) {
    import std.algorithm : max;

    auto status = tryRunCollect(args);

    yap(status.output);
    if (status.status != 0) {
        auto l = min(100, status.output.length);

        throw new ErrorLevelException(-1, status.output[0 .. l].dup);
    }
}

struct TestEnv {
    import std.ascii : newline;

    private string[] echo_;
    private Path outdir_;
    private Path dextool_;
    private File logfile;

    this(Path dextool) {
        this.dextool_ = dextool.absolutePath;
    }

    Path outdir() const {
        return outdir_;
    }

    Path dextool() const {
        return dextool_;
    }

    void echo(string s) nothrow {
        echo_ ~= s;
    }

    void echo(T...)(T args) {
        import std.format : format;

        echo_ ~= format(args);
    }

    string toString() {
        // dfmt off
        return only(
                    ["dextool:", dextool.toString],
                    ["outdir:", outdir.toString],
                    )
            .map!(a => leftJustifier(a[0], 10).text ~ a[1])
            .joiner(newline)
            .text;
        // dfmt on
    }

    void setup(Path outdir__) {
        outdir_ = outdir__.absolutePath.stripExtension;
        writeln("Test environment:", newline, toString);

        // ensure logs are empty
        if (exists(outdir)) {
            // tryRemove can fail, usually duo to I/O when tests are ran in
            // parallel.
            try {
                dirEntries(outdir, SpanMode.shallow).each!(a => tryRemove(Path(a)));
            }
            catch (FileException ex) {
                echo(ex.msg);
            }
        } else {
            mkdirRecurse(outdir);
        }

        auto stdout_path = outdir ~ "stdout.log";
        logfile = File(stdout_path.toString, "w");
    }

    void writeLog(string logname, string msg) {
        mkdirRecurse(outdir);

        auto f = File((outdir ~ logname ~ Ext(".txt")).toString, "w");
        f.write(msg);
    }

    void teardown() {
        if (!logfile.isOpen) {
            return;
        }

        // Use when saving error data for later analyze
        foreach (l; echo_) {
            logfile.writeln(l);
        }

        logfile.close();
    }
}

string EnvSetup(string logdir) {
    import std.format : format;

    auto txt = `
    import scriptlike;

    auto testEnv = TestEnv(Path("../build/dextool-debug"));
    scriptlikeCustomEcho = (string s) { testEnv.echo(s); };

    // Setup and cleanup
    chdir(thisExePath.dirName);
    scope (exit)
        testEnv.teardown();

    {
        import std.traits : fullyQualifiedName;
        int _ = 0;
        testEnv.setup(Path("%s/" ~ fullyQualifiedName!_));
    }
`;

    return format(txt, logdir);
}

struct GR {
    Path gold;
    Path result;
}

void compare(in Path gold, in Path result) {
    import std.stdio : File;

    yap("Comparing gold:'%s'\n        output:'%s'\n", gold, result);

    File goldf;
    File resultf;

    try {
        goldf = File(gold.escapePath);
        resultf = File(result.escapePath);
    }
    catch (ErrnoException ex) {
        throw new ErrorLevelException(-1, ex.msg);
    }

    bool diff_detected = false;
    int max_diff;
    foreach (idx, g, r; lockstep(goldf.byLine(), resultf.byLine())) {
        if (g.length > 2 && r.length > 2 && g[0 .. 2] == "//" && r[0 .. 2] == "//") {
            continue;
        } else if (g != r && max_diff < 5) {
            // +1 of index because editors start counting lines from 1
            yap("Line %d\t\ngold: %s\nout:  %s\n", idx + 1, g, r);
            diff_detected = true;
            ++max_diff;
        }
    }

    //TODO replace with enforce
    if (diff_detected) {
        throw new ErrorLevelException(-1,
                "Output is different from reference file (gold): " ~ gold.escapePath);
    }
}

void runDextool(in Path input, const ref TestEnv testEnv, in string[] pre_args, in string[] flags) {
    echoOn;
    scope (exit)
        echoOff;

    Args args;
    args ~= testEnv.dextool;
    args ~= pre_args.dup;
    args ~= "--out=" ~ testEnv.outdir.escapePath;
    args ~= input.escapePath;

    if (flags.length > 0) {
        args ~= "--";
        args ~= flags.dup;
    }

    import std.datetime;

    StopWatch sw;
    sw.start;
    runAndLog(args.data);
    sw.stop;

    yap("Dextool execution time in ms: " ~ sw.peek().msecs.text);
}

void compareResult(T...)(in T args) {
    static assert(args.length >= 1);

    foreach (a; args) {
        if (existsAsFile(a.gold)) {
            compare(a.gold, a.result);
        }
    }
}

void compileResult(in Path input, in Path main, const ref TestEnv testEnv,
        in string[] flags, in string[] incls) {
    echoOn;
    scope (exit)
        echoOff;

    auto binout = testEnv.outdir ~ "binary";

    Args args;
    args ~= "g++";
    args ~= flags.dup;
    args ~= "-g";
    args ~= "-o" ~ binout.escapePath;
    args ~= "-I" ~ testEnv.outdir.escapePath;
    args ~= incls.dup;
    args ~= input;
    args ~= main;

    runAndLog(args.data);
    runAndLog(binout.escapePath);
}

void demangleProfileLog(in Path out_fname) {
    echoOn;
    scope (exit)
        echoOff;

    Args args;
    args ~= "ddemangle";
    args ~= "trace.log";
    args ~= ">";
    args ~= out_fname.escapePath;

    runAndLog(args.data);
}

string[] compilerFlags() {
    echoOn;
    scope (exit)
        echoOff;

    auto default_flags = ["-std=c++98"];

    auto r = tryRunCollect("g++ -dumpversion");
    auto version_ = r.output;
    yap("Compiler version: %s\n", version_);

    if (r.status != 0) {
        return default_flags;
    }

    if (version_.length == 0) {
        return default_flags;
    } else if (version_[0] == '5') {
        return default_flags ~ ["-Wpedantic", "-Werror"];
    } else {
        return default_flags ~ ["-pedantic", "-Werror"];
    }
}
