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
    const packageDir = args[2].absolutePath;
    const dubTargetPath = environment.get("DUB_TARGET_PATH", "dub_fallback_install");

    const buildDir = buildPath(packageDir, dubTargetPath);

    const cmakeDir = buildPath(buildDir, "cmake_build");

    const postBuildStamp = buildPath(buildDir, "prebuild_dub.stamp");

    if (exists(postBuildStamp))
        return 0;

    if (!exists(cmakeDir))
        mkdirRecurse(cmakeDir);

    switch (command) {
    case "preGenerate":
        if (spawnProcess([
                    "cmake", "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_INSTALL_PREFIX=" ~ buildDir.escapeShellFileName,
                    packageDir
                ], null, Config.none, cmakeDir).wait != 0)
            return 1;
        return 0;
    case "postBuild":
        if (spawnProcess(["make", "-j", totalCPUs.to!string, "install"], null,
                Config.none, cmakeDir).wait != 0)
            return 1;
        rmdirRecurse(cmakeDir);
        File(postBuildStamp, "w").write;
        return 0;
    default:
        writeln("Unknown command");
    }

    return 1;
}
