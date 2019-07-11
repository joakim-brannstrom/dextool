#!/usr/bin/env dub
/+ dub.sdl:
    name "dub_integration"
+/
import std;

int main(string[] args) {
    if (args.length < 3) {
        writefln("Usage: %s command PACKAGE_DIR", thisExePath.baseName);
        writeln("commands: preGenerate postBuild");
        return 1;
    }

    const command = args[1];
    const packageDir = args[2];
    const dubTargetPath = environment.get("DUB_TARGET_PATH",
            buildPath(packageDir, "dub_fallback_install"));

    const buildDir = buildPath(packageDir, dubTargetPath);

    const cmakeDir = buildPath(buildDir, "cmake_build");

    const preBuildDubStamp = buildPath(cmakeDir, "prebuild_dub.stamp");

    if (!exists(cmakeDir))
        mkdirRecurse(cmakeDir);

    switch (command) {
    case "preGenerate":
        if (exists(preBuildDubStamp))
            return 0;
        if (spawnProcess([
                    "cmake", "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_INSTALL_PREFIX=" ~ buildDir.escapeShellFileName,
                    packageDir
                ], null, Config.none, cmakeDir).wait != 0)
            return 1;
        File(preBuildDubStamp, "w").write;
        return 0;
    case "postBuild":
        return spawnProcess(["make", "-j", totalCPUs.to!string, "install"],
                null, Config.none, cmakeDir).wait;
    default:
        writeln("Unknown command");
    }

    return 1;
}
