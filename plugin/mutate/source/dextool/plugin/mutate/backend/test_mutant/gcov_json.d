/**
Copyright: Copyright (c) 2026, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.plugin.mutate.backend.test_mutant.gcov_json;

import std.algorithm : filter, map;
import std.array : appender, array;
import logger = std.experimental.logger;
import std.exception : collectException, ifThrown;
import std.file : dirEntries, exists, isDir, read, readText, SpanMode;
import std.json : JSONException, JSONOptions, JSONValue, parseJSON;
import std.path : buildPath, isAbsolute;
import std.range : assumeSorted;
import std.string : endsWith;
import std.zlib : HeaderFormat, UnCompress;

import miniorm;
import my.optional;

import dextool.plugin.mutate.backend.database : CoverageRegionId, FileId;
import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Offset;
import dextool.type : AbsolutePath, Path;

@safe:

struct GcovImportStats {
    size_t inputFiles;
    size_t sourceFiles;
    size_t regionStatuses;
    bool imported;
}

private struct ImportedRegionStatus {
    CoverageRegionId id;
    bool status;
}

private struct ImportedLineStatus {
    FileId fileId;
    uint line;
    bool status;
}

private string readGcovJson(AbsolutePath path) @trusted {
    if (!path.toString.endsWith(".gz"))
        return readText(path.toString);

    scope decmp = new UnCompress(HeaderFormat.gzip);
    auto app = appender!(ubyte[])();
    app.put(cast(const(ubyte)[]) decmp.uncompress(read(path.toString)));
    app.put(cast(const(ubyte)[]) decmp.flush());
    return cast(string) app.data.idup;
}

private long[uint][Path] loadLineCoverage(FilesysIO fio, const AbsolutePath[] inputs) {
    long[uint][Path] lineCoverage;

    long jsonToLong(ref const(JSONValue) value) {
        try {
            return value.integer;
        } catch (JSONException e) {
            import std.conv : to;

            return value.str.to!long;
        }
    }

    AbsolutePath resolveSourcePath(string path, string gcovCwd, AbsolutePath input) {
        if (path.isAbsolute)
            return AbsolutePath(path);
        if (gcovCwd.length != 0)
            return AbsolutePath(buildPath(gcovCwd, path));
        return AbsolutePath(buildPath(input.dirName.toString, path));
    }

    void addLineCoverage(Path source, uint lineNumber, long count) {
        if (auto fileCoverage = source in lineCoverage) {
            if (auto existing = lineNumber in *fileCoverage) {
                *existing += count;
            } else {
                (*fileCoverage)[lineNumber] = count;
            }
        } else {
            lineCoverage[source] = [lineNumber: count];
        }
    }

    foreach (input; inputs) {
        JSONValue json;
        try {
            json = parseJSON(readGcovJson(input), JSONOptions.doNotEscapeSlashes);
        } catch (Exception e) {
            logger.warningf("Failed to parse gcov json %s: %s", input, e.msg).collectException;
            continue;
        }

        const gcovCwd = ifThrown(json["current_working_directory"].str, string.init);

        JSONValue files;
        try {
            files = json["files"];
        } catch (Exception e) {
            logger.warningf("Object 'files' not found in gcov json %s", input).collectException;
            continue;
        }

        JSONValue[] fileEntries;
        try {
            fileEntries = files.arrayNoRef;
        } catch (Exception e) {
            logger.warningf("Object 'files' in gcov json %s must be an array: %s", input, e.msg)
                .collectException;
            continue;
        }

        foreach (fileEntry; fileEntries) {
            try {
                const source = resolveSourcePath(fileEntry["file"].str, gcovCwd, input);
                auto relSource = fio.toRelativeRoot(Path(source.toString));
                foreach (lineEntry; fileEntry["lines"].arrayNoRef) {
                    const lineNumber = cast(uint) jsonToLong(lineEntry["line_number"]);
                    const count = jsonToLong(lineEntry["count"]);
                    addLineCoverage(relSource, lineNumber, count);
                }
            } catch (Exception e) {
                logger.warningf("Skipping malformed gcov file entry in %s: %s", input, e.msg)
                    .collectException;
            }
        }
    }

    return lineCoverage;
}

private uint[] lineStarts(const(ubyte)[] content) {
    auto starts = appender!(uint[])();
    starts.put(0);
    foreach (i, b; content) {
        if (b == '\n' && i + 1 < content.length)
            starts.put(cast(uint)(i + 1));
    }
    return starts.data;
}

private Optional!bool statusForRegion(const Offset region, const uint[] starts, const long[uint] lineCounts) {
    uint lineNumberAt(uint offset) {
        if (starts.length == 0)
            return 1;
        return cast(uint)(starts.length - assumeSorted(starts).upperBound(offset).length);
    }

    const beginLine = lineNumberAt(region.begin);
    const endLine = lineNumberAt(region.isZero ? region.begin : region.end - 1);

    bool sawLine;
    bool covered;
    foreach (line; beginLine .. endLine + 1) {
        if (auto count = line in lineCounts) {
            sawLine = true;
            covered = covered || *count > 0;
        }
    }

    if (!sawLine)
        return none!bool;

    return some(covered);
}

GcovImportStats importGcovJsonCoverage(FilesysIO fio, Database* db,
        const AbsolutePath[] rawInputs) @trusted {
    bool isGcovJsonFile(string path) @safe pure nothrow {
        return path.endsWith(".gcov.json") || path.endsWith(".gcov.json.gz");
    }

    AbsolutePath[] findAllGcovJson(AbsolutePath inputDir) {
        if (!isDir(inputDir))
            return typeof(return).init;

        auto gcovFiles = dirEntries(inputDir.toString, SpanMode.depth)
            .filter!(a => !a.isDir && isGcovJsonFile(a.name))
            .map!(a => AbsolutePath(a.name))
            .array;

        if (gcovFiles.length == 0)
            logger.warningf("No gcov json files found in %s", inputDir).collectException;

        return gcovFiles;
    }

    auto inputFiles = appender!(AbsolutePath[])();
    foreach (rawInput; rawInputs) {
        if (!exists(rawInput)) {
            logger.warningf("gcov json input does not exist: %s", rawInput).collectException;
            continue;
        }

        if (isDir(rawInput)) {
            inputFiles.put(findAllGcovJson(rawInput));
            continue;
        }

        if (!isGcovJsonFile(rawInput.toString)) {
            logger.warningf("gcov json input must end in .gcov.json or .gcov.json.gz: %s",
                    rawInput).collectException;
            continue;
        }

        inputFiles.put(rawInput);
    }

    const inputs = inputFiles.data;
    spinSql!(() => db.coverageApi.clearImportedLineCoverage);
    if (inputs.length == 0)
        logger.warning("No gcov json input files were found").collectException;
    if (inputs.length == 0)
        return GcovImportStats(0, 0, 0, false);

    auto importedCoverage = loadLineCoverage(fio, inputs);
    auto regionsByFile = spinSql!(() => db.coverageApi.getCoverageMap);
    if (regionsByFile.length == 0) {
        logger.warning(
                "No analyzed coverage regions found. Re-run analyze with [coverage].use = true before importing gcov JSON.")
            .collectException;
        return GcovImportStats(inputs.length, 0, 0, false);
    }

    struct ImportedCoverageMatch {
        size_t matchedFiles;
        ImportedLineStatus[] lines;
        ImportedRegionStatus[] statuses;
    }

    ImportedCoverageMatch matchImportedCoverage() {
        auto importedStatuses = appender!(ImportedRegionStatus[])();
        auto importedLines = appender!(ImportedLineStatus[])();
        size_t matchedFiles;

        foreach (entry; regionsByFile.byKeyValue) {
            auto relPath = spinSql!(() => db.getFile(entry.key));
            if (relPath.isNull)
                continue;

            if (auto lineCounts = relPath.get in importedCoverage) {
                auto raw = fio.makeInput(fio.toAbsoluteRoot(relPath.get)).content;
                const starts = lineStarts(raw);
                matchedFiles++;

                foreach (lineEntry; lineCounts.byKeyValue) {
                    importedLines.put(ImportedLineStatus(entry.key, lineEntry.key,
                            lineEntry.value > 0));
                }

                foreach (region; entry.value) {
                    auto status = statusForRegion(region.region, starts, *lineCounts);
                    if (status.hasValue)
                        importedStatuses.put(ImportedRegionStatus(region.id,
                                status.orElse(false)));
                }
            }
        }

        return ImportedCoverageMatch(matchedFiles, importedLines.data, importedStatuses.data);
    }

    auto matchedCoverage = matchImportedCoverage();
    if (matchedCoverage.matchedFiles == 0) {
        logger.warning(
                "None of the gcov json files matched analyzed source files in the current work area.")
            .collectException;
        return GcovImportStats(inputs.length, 0, 0, false);
    }

    spinSql!(() @trusted {
        auto trans = db.transaction;
        db.coverageApi.clearCoverageInfo;
        foreach (entry; matchedCoverage.lines) {
            db.coverageApi.putImportedLineCoverage(entry.fileId, entry.line, entry.status);
        }
        foreach (entry; matchedCoverage.statuses) {
            db.coverageApi.putCoverageInfo(entry.id, entry.status);
        }
        db.coverageApi.updateCoverageTimeStamp;
        trans.commit;
    });

    return GcovImportStats(inputs.length, matchedCoverage.matchedFiles,
            matchedCoverage.statuses.length, true);
}
