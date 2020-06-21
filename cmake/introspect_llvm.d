#!/usr/bin/env dub
/+ dub.sdl:
    name "introspect_llvm"
+/
/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file extract information about the LLVM installation.
*/
import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.range;
import std.stdio;
import std.string;
import std.variant;
import std.typecons;
import std.utf;

int main(string[] args) {
    if (args.length != 2) {
        writeln("Missing command");
        return 1;
    }

    alias Fun = string function();
    Fun[string] cmds;
    cmds["ldflags"] = &llvmLdflags;
    cmds["libs"] = &llvmLibs;
    cmds["version"] = &llvmVersion;
    cmds["cpp-flags"] = &llvmCppFlags;
    cmds["libdir"] = &llvmLibdir;
    cmds["libclang"] = &llvmLibClang;
    cmds["libclang-flags"] = &llvmClangFlags;
    cmds["print-llvm-config-candidates"] = &llvmPrintCandidates;

    if (auto f = args[1] in cmds)
        write((*f)().strip);
    else {
        writeln("Unknown commad: ", args[1]);
    }

    return 0;
}

string llvmPrintCandidates() {
    return llvmCmd(true);
}

string llvmLdflags() {
    return execute([llvmCmd, "--ldflags"]).output.strip;
}

string[] osSpecificLinkerFlag() {
    // The MacOSX linker do not support this flag
    version (OSX) {
        return null;
    } else {
        return ["-Wl,--enable-new-dtags", "-Wl,--no-as-needed"];
    }
}

string llvmLibs() {
    const string[] base = osSpecificLinkerFlag;
    const string[] libdir = ["-Wl,-rpath", llvmLibdir];

    // sometimes llvm-config forget the dependency on c and c++ stdlib
    const string[] deps = ["-lstdc++", "-lc", "-lm"];

    const string llvm = () {
        // using two separate calls because it makes it possible to
        // differentiate between finding the llvm lib and the system
        // dependencies. also because llvm-config print a newline for each CLI
        // parameter which results in broken cmake files.
        const s0 = execute([llvmCmd, "--libs"]).output.strip;
        // prepend with space so it can always be appended
        const s1 = " " ~ (execute([llvmCmd, "--system-libs"]).output.strip);
        const s = s0 ~ s1;

        if (s0.length != 0)
            return s;

        return findLib("libLLVM", PartialLibrary("LLVM")).visit!(
                (AbsLibrary a) => cast(string) a ~ s1, (PartialLibrary a) => cast(string) a ~ s1);
    }();

    return (base ~ libdir ~ [llvm].dup ~ deps).joiner(" ").toUTF8;
}

string llvmVersion() {
    import std.regex;

    immutable re_NUM = "[0-9]+";

    const llvm_conf = execute([llvmCmd, "--version"]).output.strip;

    if (llvm_conf.length == 0) {
        // a sane default
        return "LLVM_4_0_0";
    }

    auto parts = matchAll(llvm_conf, re_NUM).map!(a => a.hit).array;
    if (parts.length < 3)
        parts ~= "0";

    return "LLVM_" ~ parts.joiner("_").toUTF8;
}

string llvmCppFlags() {
    const flags = execute([llvmCmd, "--cxxflags"]);
    return flags.output.strip;
}

string llvmLibdir() {
    return execute([llvmCmd, "--libdir"]).output.strip;
}

string llvmLibClang() {
    return findLib("libclang.so", PartialLibrary("clang")).visit!(
            (AbsLibrary a) => cast(string) a, (PartialLibrary a) => cast(string) a);
}

string llvmClangFlags() {
    const string[] base = osSpecificLinkerFlag;

    const string[] libdir = ["-L" ~ llvmLibdir, "-Wl,-rpath", llvmLibdir];

    const string lib = findLib("libclang.so", PartialLibrary("clang")).visit!(
            (AbsLibrary a) => "-l:" ~ cast(string) a, (PartialLibrary a) => "-l" ~ cast(string) a);

    return (base ~ libdir ~ [lib].dup).joiner(" ").toUTF8;
}

alias PartialLibrary = Typedef!(string, null, "PartialLibrary");
alias AbsLibrary = Typedef!(string, null, "FullLibrary");
alias Library = Algebraic!(AbsLibrary, PartialLibrary);

/** Find the first file in the search paths that contain the sought after word.
 */
Library findLib(string lib, PartialLibrary backup) {
    // dfmt off
    foreach (p; llvmSearchPaths
             .filter!(a => exists(a))
             .map!(a => dirEntries(a, SpanMode.shallow))
             .joiner
             .filter!(a => a.isFile)
             .map!(a => std.path.baseName(a.name))
             .filter!(a => a.canFind(lib))) {
        return AbsLibrary(p).Library;
    }
    // dfmt on

    return backup.Library;
}

/** The order the paths are listed affects the priority. The higher up the
 * higher priority because only the first match is used.
 */
string[] llvmSearchPaths() {
    // dfmt off
    return [
        llvmLibdir,
        // Ubuntu
        "/usr/lib/llvm-10/lib",
        "/usr/lib/llvm-9/lib",
        "/usr/lib/llvm-8/lib",
        "/usr/lib/llvm-7/lib",
        "/usr/lib/llvm-6.0/lib",
        "/usr/lib/llvm-5.0/lib",
        "/usr/lib/llvm-4.0/lib",
        "/usr/lib/llvm-3.9/lib",
        // MacOSX
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib",
        "/Applications/Xcode.app/Contents/Frameworks",
        // fallback
        "/usr/lib64/llvm",
    ];
    // dfmt on
}

/** Find a suitable llvm-config to use.

  The primary is llvm-config. But not all systems have one installed but rather specific llvm-config for matching the lib version.
  As fallback try to use the "latest" llvm-config.
  */
string llvmCmd(bool print_candidates = false) {
    import std.regex : regex, matchFirst;

    immutable llvm_cmd = "llvm-config";
    auto reVersion = regex(`.*llvm-config-(?P<nr>.*)`);

    Llvm makeLlvm(string s) {
        auto m = matchFirst(s, reVersion);
        if (m.empty)
            return Llvm(SemVer.init, s);
        return Llvm(SemVer.make(m["nr"]), s);
    }

    // try to see if it works as-is.
    try {
        if (execute([llvm_cmd, "-h"]).status == 0)
            return llvm_cmd;
    } catch (Exception e) {
    }

    // dfmt off
    Llvm[] candidates = environment.get("PATH", null)
        .splitter(":")
        .filter!(a => !a.empty)
        .filter!(a => exists(a))
        .map!(a => dirEntries(a, SpanMode.shallow))
        .map!(a => a.map!(a => a.name))
        .joiner
        .filter!(a => exists(a))
        .filter!(a => a.baseName.startsWith(llvm_cmd))
        .map!(a => makeLlvm(a))
        .array
        .sort!((a,b) => a.v > b.v)
        .array;
    // dfmt on

    if (print_candidates) {
        writefln("llvm-config candidates: \n%(%s\n%)", candidates);
        writeln("Using:");
    }

    foreach (a; candidates)
        return a.cmd;
    return llvm_cmd;
}

struct Llvm {
    SemVer v;
    string cmd;
}

/// Semantic version
struct SemVer {
    private int[3] value;

    int major() {
        return value[0];
    }

    int minor() {
        return value[0];
    }

    int bugFix() {
        return value[0];
    }

    int opCmp(ref const typeof(this) rhs) const {
        foreach (i; 0 .. value.length) {
            if (value[i] < rhs.value[i])
                return -1;
            if (value[i] > rhs.value[i])
                return 1;
        }
        return 0;
    }

    bool opEquals()(auto ref const SemVer s) const {
        return value == s.value;
    }

    static SemVer make(string s) {
        import std.conv : to;
        import std.regex : regex, matchFirst;

        SemVer rval;

        const re = regex(`^(?:(\d+)\.)?(?:(\d+)\.)?(\d+)$`);
        auto m = matchFirst(s, re);
        if (m.empty)
            return rval;

        try {
            foreach (a; m.dropOne.filter!(a => !a.empty).enumerate) {
                rval.value[a.index] = a.value.to!int;
            }
        } catch (Exception e) {
        }

        return rval;
    }
}

unittest {
    assert(SemVer.make("1.2.3") == [1, 2, 3]);
    assert(SemVer.make("1.2") == [1, 2, 0]);
    assert(SemVer.make("1") == [1, 0, 0]);
    assert(SemVer.make("1.2.3.4") == [1, 2, 3]);
}
