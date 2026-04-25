/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_coverage;

import std.algorithm : any, canFind, map;
import std.array : appender, array, join;
import std.file : mkdirRecurse, read, readText, write;
import std.format : format;
import std.json : JSONValue, parseJSON;
import std.path : absolutePath, buildPath, pathSplitter, relativePath;
import std.range : assumeSorted;
import std.zlib : Compress, HeaderFormat;

import dextool.plugin.mutate.backend.database.standalone : Database;
import dextool.plugin.mutate.backend.type : ExitStatus, Mutation, Offset;
import dextool.type : Path;

import dextool_test.utility;
import dextool_test.fixtures;

private final class CoverageFixtureInstance : CoverageFixutre {
    override void test() {
    }
}

private final class PreciseImportedCoverageFixture : CoverageFixutre {
    override void test() {
    }

    override string programFile() {
        return (testData ~ "gcov_precise_branch.cpp").toString;
    }
}

private struct GcovLineSpec {
    long lineNumber;
    long count;
    string functionName;
}

private struct GcovJsonWriteOptions {
    string cwd = ".";
    bool includeCwd = true;
    bool includeFiles = true;
    bool gzip;
    bool stringifyNumbers;
}

private struct LineRange {
    uint beginLine;
    uint endLine;
}

private struct CoverageLineStatus {
    LineRange lines;
    bool status;
}

private struct CoverageView {
    CoverageLineStatus[] known;
    LineRange[] unknown;
}

private immutable GcovLineSpec[] coverFunctionCoveredLines = [
    GcovLineSpec(47, 2, "cover"),
    GcovLineSpec(48, 2, "cover"),
    GcovLineSpec(49, 1, "cover"),
    GcovLineSpec(51, 1, "cover"),
    GcovLineSpec(54, 1, "cover")
];

private immutable GcovLineSpec[] coverFunctionCoveredLinesWithZeroCount = [
    GcovLineSpec(47, 2, "cover"),
    GcovLineSpec(48, 2, "cover"),
    GcovLineSpec(49, 1, "cover"),
    GcovLineSpec(51, 1, "cover"),
    GcovLineSpec(52, 0, "cover"),
    GcovLineSpec(54, 1, "cover")
];

private immutable GcovLineSpec[] unusedFunctionUncoveredLines = [
    GcovLineSpec(57, 0, "unused"),
    GcovLineSpec(58, 0, "unused"),
    GcovLineSpec(59, 0, "unused"),
    GcovLineSpec(61, 0, "unused")
];

private immutable GcovLineSpec[] mainFunctionCoveredLines = [
    GcovLineSpec(64, 1, "main"),
    GcovLineSpec(65, 1, "main"),
    GcovLineSpec(66, 1, "main"),
    GcovLineSpec(67, 1, "main"),
    GcovLineSpec(68, 1, "main"),
    GcovLineSpec(69, 1, "main")
];

private immutable GcovLineSpec[] preciseBranchCoveredLines = [
    GcovLineSpec(2, 1, "compute"),
    GcovLineSpec(3, 1, "compute")
];

private immutable GcovLineSpec[] preciseBranchUncoveredLines = [
    GcovLineSpec(5, 0, "compute")
];

private immutable GcovLineSpec[] preciseMainCoveredLines = [
    GcovLineSpec(9, 1, "main"),
    GcovLineSpec(10, 1, "main")
];

private CoverageFixtureInstance setupCoverageFixture(ref TestEnv testEnv) {
    auto fixture = new CoverageFixtureInstance;
    fixture.precondition(testEnv);
    return fixture;
}

private PreciseImportedCoverageFixture setupPreciseImportedCoverageFixture(ref TestEnv testEnv) {
    auto fixture = new PreciseImportedCoverageFixture;
    fixture.precondition(testEnv);
    return fixture;
}

private string defaultCoverageConfig() {
    return (testData ~ "config/coverage.toml").toString;
}

private string writeConfig(ref TestEnv testEnv, string fileName, string content) {
    const path = (testEnv.outdir ~ fileName).toString;
    write(path, content);
    return path;
}

private string coverageConfigText(string extraCoverage = "") {
    const coverage = extraCoverage.length == 0 ? "use = true" : format("use = true\n%s",
            extraCoverage);
    return format(`[generic]
mutants = ["lcr", "lcrb", "sdl", "uoi", "dcr"]

[coverage]
%s

[mutant_test]
test_cmd_timeout = "10 seconds"
`, coverage);
}

private string analyzeWithoutCoverageConfigText() {
    return `[generic]
mutants = ["lcr", "lcrb", "sdl", "uoi", "dcr"]

[mutant_test]
test_cmd_timeout = "10 seconds"
`;
}

private string pathToHtmlName(string p) {
    return p.pathSplitter.join("__");
}

private JSONValue makeGcovLine(GcovLineSpec spec,
        GcovJsonWriteOptions options = GcovJsonWriteOptions()) {
    JSONValue line;
    JSONValue[] branches;
    if (options.stringifyNumbers) {
        line["line_number"] = format("%s", spec.lineNumber);
        line["count"] = format("%s", spec.count);
    } else {
        line["line_number"] = spec.lineNumber;
        line["count"] = spec.count;
    }
    line["function_name"] = spec.functionName;
    line["unexecuted_block"] = spec.count == 0;
    line["branches"] = JSONValue(branches);
    return line;
}

private JSONValue makeGcovFileData(string sourceFile, const(GcovLineSpec)[] lines,
        GcovJsonWriteOptions options = GcovJsonWriteOptions()) {
    JSONValue fileData;
    JSONValue[] functions;

    fileData["file"] = sourceFile;
    fileData["functions"] = JSONValue(functions);
    fileData["lines"] = JSONValue(lines.map!(a => makeGcovLine(a, options)).array);
    return fileData;
}

private void writeGcovJsonRoot(string path, JSONValue root, bool gzip) {
    const content = root.toString;
    if (!gzip) {
        write(path, content);
        return;
    }

    auto cmp = new Compress(HeaderFormat.gzip);
    auto compressed = appender!(ubyte[])();
    compressed.put(cast(const(ubyte)[]) cmp.compress(content));
    compressed.put(cast(const(ubyte)[]) cmp.flush());
    write(path, compressed.data);
}

private void writeGcovJsonFiles(string path, JSONValue[] files,
        GcovJsonWriteOptions options = GcovJsonWriteOptions()) {
    JSONValue root;

    if (options.includeCwd)
        root["current_working_directory"] = options.cwd;
    root["data_file"] = "simple_coverage.gcda";
    root["format_version"] = 1;
    root["gcc_version"] = "13.0.0";
    if (options.includeFiles)
        root["files"] = JSONValue(files);

    writeGcovJsonRoot(path, root, options.gzip);
}

private void writeGcovJson(string path, string sourceFile, const(GcovLineSpec)[] lines,
        GcovJsonWriteOptions options = GcovJsonWriteOptions()) {
    writeGcovJsonFiles(path, [makeGcovFileData(sourceFile, lines, options)], options);
}

private GcovLineSpec[] withCount(const(GcovLineSpec)[] lines, long count) {
    return lines.map!(a => GcovLineSpec(a.lineNumber, count, a.functionName)).array;
}

private void analyzeCoverageProgram(ref TestEnv testEnv, CoverageFixutre fixture,
        string configPath = null) {
    auto cmd = makeDextoolAnalyze(testEnv)
        .argDebug(false)
        .addInputArg(fixture.programCode)
        .addPostArg(["--mutant", "all"]);

    if (configPath.length != 0)
        cmd.addPostArg(["-c", configPath]);

    cmd.run;
}

private auto makeCoverageTestCommand(ref TestEnv testEnv, CoverageFixutre fixture,
        string configPath, bool throwOnExitStatus = true) {
    auto cmd = dextool_test.makeDextool(testEnv)
        .setWorkdir(workDir)
        .args(["mutate"])
        .addArg(["test"])
        .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
        .addPostArg("--no-skipped")
        .addPostArg(["--build-cmd", fixture.compileScript])
        .addPostArg(["--test-cmd", fixture.testScript])
        .addPostArg(["--log-coverage"])
        .argDebug(false)
        .throwOnExitStatus(throwOnExitStatus);

    if (configPath.length != 0)
        cmd.addPostArg(["-c", configPath]);

    return cmd;
}

private auto runCoverageTest(ref TestEnv testEnv, CoverageFixutre fixture, string configPath,
        string[][] extraPostArgs = null, bool throwOnExitStatus = true) {
    auto cmd = makeCoverageTestCommand(testEnv, fixture, configPath, throwOnExitStatus);
    foreach (args; extraPostArgs)
        cmd.addPostArg(args);
    return cmd.run;
}

private JSONValue coverageReportStat(ref TestEnv testEnv) {
    makeDextoolReport(testEnv, testData.dirName)
        .argDebug(false)
        .addPostArg(["--style", "json"])
        .addPostArg(["--section", "summary", "--section", "all_mut"])
        .addPostArg(["--logdir", testEnv.outdir.toString])
        .run;
    return parseJSON(readText((testEnv.outdir ~ "report.json").toString))["stat"];
}

private string coverageHtmlProgramPage(ref TestEnv testEnv, CoverageFixutre fixture) {
    makeDextoolReport(testEnv, testData.dirName)
        .argDebug(false)
        .addPostArg(["--style", "html"])
        .addPostArg(["--section", "summary", "--section", "all_mut"])
        .addPostArg(["--logdir", testEnv.outdir.toString])
        .run;

    auto db = openDatabase(testEnv);
    const fileId = coverageFileId(db, fixture);
    auto filePath = db.getFile(fileId);
    filePath.isNull.shouldBeFalse;

    return readText((testEnv.outdir ~ format("html/files/%s.html",
            pathToHtmlName(filePath.get))).toString);
}

private void htmlLineShouldHaveCoverageClass(string html, uint line, string cssClass) {
    html.canFind(format(`id="loc-%s"><span class="line_nr %s">%s:`, line, cssClass, line))
        .shouldBeTrue;
}

private void assertCoverageInstrumentationOutput(string[] output) {
    testAnyOrder!SubStr([
        "Compiling instrumented source code",
        "Coverage instrumenting"
    ]).shouldBeIn(output);
}

private void assertBuiltInCoverageOutput(string[] output) {
    assertCoverageInstrumentationOutput(output);
    testAnyOrder!SubStr([
        "Importing coverage from gcov --json-format"
    ]).shouldNotBeIn(output);
}

private void assertImportedCoverageOutput(string[] output, size_t inputs = 1) {
    testAnyOrder!SubStr([
        "Importing coverage from gcov --json-format",
        format("Imported gcov json coverage (%s inputs,", inputs)
    ]).shouldBeIn(output);
    testAnyOrder!SubStr([
        "Compiling instrumented source code",
        "Coverage instrumenting"
    ]).shouldNotBeIn(output);
}

private uint[] lineStarts(const(ubyte)[] content) {
    auto starts = appender!(uint[])();
    starts.put(0);
    foreach (i, b; content) {
        if (b == '\n' && i + 1 < content.length)
            starts.put(cast(uint) (i + 1));
    }
    return starts.data;
}

private uint lineNumberAt(const uint[] starts, uint offset) @safe pure nothrow {
    if (starts.length == 0)
        return 1;
    return cast(uint) (starts.length - assumeSorted(starts).upperBound(offset).length);
}

private LineRange lineRangeForRegion(Offset region, const uint[] starts) @safe pure nothrow {
    return LineRange(lineNumberAt(starts, region.begin),
            lineNumberAt(starts, region.isZero ? region.begin : region.end - 1));
}

private string regionKey(Offset region) {
    return format("%s:%s", region.begin, region.end);
}

private Path dbProgramPath(CoverageFixutre fixture) {
    const relative = relativePath(fixture.programCode, workDir.toString);
    return relative == fixture.programCode ? Path("program.cpp") : Path(relative);
}

private auto coverageFileId(ref Database db, CoverageFixutre fixture) {
    auto allCoverage = db.coverageApi.getCoverageMap;
    auto fileId = db.getFileId(Path("program.cpp"));
    if (fileId.isNull)
        fileId = db.getFileId(dbProgramPath(fixture));
    if (fileId.isNull && allCoverage.length == 1) {
        foreach (id; allCoverage.byKey) {
            fileId = id;
            break;
        }
    }
    fileId.isNull.shouldBeFalse;

    return fileId.get;
}

private CoverageView loadCoverageView(ref TestEnv testEnv, CoverageFixutre fixture) {
    auto db = openDatabase(testEnv);
    auto allCoverage = db.coverageApi.getCoverageMap;
    const fileId = coverageFileId(db, fixture);

    auto fileRegions = fileId in allCoverage;
    (fileRegions !is null).shouldBeTrue;

    auto knownStatus = db.coverageApi.getCoverageStatus(fileId);
    bool[string] knownByRegion;
    foreach (status; knownStatus)
        knownByRegion[regionKey(status.region)] = status.status;

    const starts = lineStarts(cast(const(ubyte)[]) read(fixture.programCode));
    CoverageView view;
    foreach (region; *fileRegions) {
        const key = regionKey(region.region);
        const lines = lineRangeForRegion(region.region, starts);
        if (auto status = key in knownByRegion) {
            view.known ~= CoverageLineStatus(lines, *status);
        } else {
            view.unknown ~= lines;
        }
    }

    return view;
}

private bool[uint] loadImportedLineCoverage(ref TestEnv testEnv, CoverageFixutre fixture) {
    auto db = openDatabase(testEnv);
    return db.coverageApi.getImportedLineCoverage(coverageFileId(db, fixture));
}

private Mutation.Status[] mutantStatusesAtLine(ref TestEnv testEnv, CoverageFixutre fixture, uint line) {
    auto db = openDatabase(testEnv);
    static immutable sql = "SELECT DISTINCT t0.status FROM mutation_status t0, mutation t1, mutation_point t2 "
        ~ "WHERE t0.id = t1.st_id AND t1.mp_id = t2.id AND t2.file_id = :fid "
        ~ "AND :line BETWEEN t2.line AND t2.line_end";

    auto stmt = db.db.prepare(sql);
    stmt.get.bind(":fid", coverageFileId(db, fixture).get);
    stmt.get.bind(":line", line);

    auto rval = appender!(Mutation.Status[])();
    foreach (ref r; stmt.get.execute) {
        rval.put(cast(Mutation.Status) r.peek!long(0));
    }
    return rval.data;
}

private bool intersects(LineRange range, uint beginLine, uint endLine) @safe pure nothrow {
    return !(range.endLine < beginLine || endLine < range.beginLine);
}

private bool hasKnownStatus(CoverageView view, uint beginLine, uint endLine, bool status) {
    return view.known.any!(a => a.status == status && intersects(a.lines, beginLine, endLine));
}

private bool hasUnknownStatus(CoverageView view, uint beginLine, uint endLine) {
    return view.unknown.any!(a => intersects(a, beginLine, endLine));
}

private void resetMutantsToUnknown(ref TestEnv testEnv) {
    auto db = openDatabase(testEnv);
    foreach (id; db.mutantApi.getAllMutationStatus)
        db.mutantApi.update(id, Mutation.Status.unknown, ExitStatus(0));
}

@(testId ~ "shall use built in coverage instrumentation when gcov json is not configured")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig);
    assertBuiltInCoverageOutput(testRun.output);

    auto stat = coverageReportStat(testEnv);
    stat["alive"].integer.shouldBeGreaterThan(2);
    stat["killed"].integer.shouldBeGreaterThan(1);
    stat["no_coverage"].integer.shouldBeGreaterThan(1);
}

@(testId ~ "shall import gcov json coverage and bypass built in instrumentation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "simple_coverage.gcov.json.gz").toString;
    writeGcovJson(gcovJson, fixture.programCode,
            coverFunctionCoveredLinesWithZeroCount ~ unusedFunctionUncoveredLines
            ~ mainFunctionCoveredLines, GcovJsonWriteOptions(gzip: true));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);

    auto stat = coverageReportStat(testEnv);
    stat["alive"].integer.shouldBeGreaterThan(1);
    stat["killed"].integer.shouldBeGreaterThan(0);
    stat["no_coverage"].integer.shouldBeGreaterThan(1);
}

@(testId ~ "shall render imported gcov coverage precisely in the html file report")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupPreciseImportedCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "precise_report.gcov.json.gz").toString;
    writeGcovJson(gcovJson, fixture.programCode,
            preciseBranchCoveredLines ~ preciseBranchUncoveredLines ~ preciseMainCoveredLines,
            GcovJsonWriteOptions(gzip: true));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);

    const html = coverageHtmlProgramPage(testEnv, fixture);
    htmlLineShouldHaveCoverageClass(html, 3, "loc_covered");
    htmlLineShouldHaveCoverageClass(html, 5, "loc_noncovered");
}

@(testId ~ "shall use imported gcov line coverage when propagating no coverage mutants")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupPreciseImportedCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "precise_no_coverage.gcov.json.gz").toString;
    writeGcovJson(gcovJson, fixture.programCode,
            preciseBranchCoveredLines ~ preciseBranchUncoveredLines ~ preciseMainCoveredLines,
            GcovJsonWriteOptions(gzip: true));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);

    auto uncoveredStatuses = mutantStatusesAtLine(testEnv, fixture, 5);
    uncoveredStatuses.length.shouldBeGreaterThan(0);
    uncoveredStatuses.canFind(Mutation.Status.noCoverage).shouldBeTrue;

    auto coveredStatuses = mutantStatusesAtLine(testEnv, fixture, 2);
    coveredStatuses.length.shouldBeGreaterThan(0);
    coveredStatuses.canFind(Mutation.Status.noCoverage).shouldBeFalse;
}

@(testId ~ "shall map gcov counts to covered uncovered and unknown regions")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "region-status.gcov.json.gz").toString;
    writeGcovJson(gcovJson, fixture.programCode,
            coverFunctionCoveredLines ~ unusedFunctionUncoveredLines,
            GcovJsonWriteOptions(gzip: true));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);
    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);

    auto coverage = loadCoverageView(testEnv, fixture);
    hasKnownStatus(coverage, 47, 54, true).shouldBeTrue;
    hasKnownStatus(coverage, 57, 61, false).shouldBeTrue;
    hasUnknownStatus(coverage, 64, 69).shouldBeTrue;
}

@(testId ~ "shall replace old imported coverage on reimport")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const firstJson = (testEnv.outdir ~ "first.gcov.json.gz").toString;
    const secondJson = (testEnv.outdir ~ "second.gcov.json.gz").toString;
    writeGcovJson(firstJson, fixture.programCode,
            coverFunctionCoveredLines ~ unusedFunctionUncoveredLines,
            GcovJsonWriteOptions(gzip: true));
    writeGcovJson(secondJson, fixture.programCode,
            coverFunctionCoveredLines ~ mainFunctionCoveredLines,
            GcovJsonWriteOptions(gzip: true));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    runCoverageTest(testEnv, fixture, defaultCoverageConfig, [["--gcov-json", firstJson]]);
    auto firstCoverage = loadCoverageView(testEnv, fixture);
    auto firstImportedCoverage = loadImportedLineCoverage(testEnv, fixture);
    auto firstUncoveredLine = 57u in firstImportedCoverage;
    hasKnownStatus(firstCoverage, 57, 61, false).shouldBeTrue;
    (firstUncoveredLine !is null).shouldBeTrue;
    (*firstUncoveredLine).shouldBeFalse;

    resetMutantsToUnknown(testEnv);

    auto secondRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", secondJson]]);
    assertImportedCoverageOutput(secondRun.output);

    auto secondCoverage = loadCoverageView(testEnv, fixture);
    auto secondImportedCoverage = loadImportedLineCoverage(testEnv, fixture);
    auto secondUncoveredLine = 57u in secondImportedCoverage;
    auto secondCoveredLine = 64u in secondImportedCoverage;
    hasKnownStatus(secondCoverage, 57, 61, false).shouldBeFalse;
    hasUnknownStatus(secondCoverage, 57, 61).shouldBeTrue;
    (secondUncoveredLine is null).shouldBeTrue;
    (secondCoveredLine !is null).shouldBeTrue;
    (*secondCoveredLine).shouldBeTrue;
}

@(testId ~ "shall import relative source paths from uncompressed gcov json via cli")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "relative.gcov.json").toString;
    writeGcovJson(gcovJson, "program.cpp", coverFunctionCoveredLines ~ mainFunctionCoveredLines,
            GcovJsonWriteOptions(includeCwd: false));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);

    auto stat = coverageReportStat(testEnv);
    stat["killed"].integer.shouldBeGreaterThan(0);
}

@(testId ~ "shall enable coverage when gcov json is provided via cli")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "cli_enables_coverage.gcov.json").toString;
    writeGcovJson(gcovJson, "program.cpp", coverFunctionCoveredLines ~ mainFunctionCoveredLines,
            GcovJsonWriteOptions(includeCwd: false));

    const configPath = writeConfig(testEnv, "test_without_coverage_use.toml",
            analyzeWithoutCoverageConfigText);

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, configPath,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);

    auto stat = coverageReportStat(testEnv);
    stat["killed"].integer.shouldBeGreaterThan(0);
}

@(testId ~ "shall enable coverage when gcov json is provided via toml")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "toml_enables_coverage.gcov.json.gz").toString;
    writeGcovJson(gcovJson, absolutePath(fixture.programCode),
            coverFunctionCoveredLines ~ mainFunctionCoveredLines,
            GcovJsonWriteOptions(gzip: true));

    const configPath = writeConfig(testEnv, "toml_gcov_without_coverage_use.toml",
            analyzeWithoutCoverageConfigText ~ format(`
[coverage]
gcov_json = "%s"
`, gcovJson));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, configPath);
    assertImportedCoverageOutput(testRun.output);

    auto stat = coverageReportStat(testEnv);
    stat["killed"].integer.shouldBeGreaterThan(0);
}

@(testId ~ "shall import gcov json when line numbers and counts are strings")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "string_numbers.gcov.json").toString;
    writeGcovJson(gcovJson, "program.cpp", coverFunctionCoveredLines ~ mainFunctionCoveredLines,
            GcovJsonWriteOptions(includeCwd: false, stringifyNumbers: true));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);

    auto coverage = loadCoverageView(testEnv, fixture);
    hasKnownStatus(coverage, 47, 54, true).shouldBeTrue;
}

@(testId ~ "shall resolve gcov source paths using current_working_directory from a directory input")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovDir = (testEnv.outdir ~ "coverage").toString;
    mkdirRecurse(gcovDir);
    const gcovJson = buildPath(gcovDir, "cwd.gcov.json.gz");
    writeGcovJson(gcovJson, "program.cpp", coverFunctionCoveredLines ~ mainFunctionCoveredLines,
            GcovJsonWriteOptions(cwd: testEnv.outdir.toString, gzip: true));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovDir]]);
    assertImportedCoverageOutput(testRun.output);

    auto stat = coverageReportStat(testEnv);
    stat["killed"].integer.shouldBeGreaterThan(0);
}

@(testId ~ "shall import gcov json from single-string toml config using absolute source paths")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "toml.gcov.json.gz").toString;
    writeGcovJson(gcovJson, absolutePath(fixture.programCode),
            coverFunctionCoveredLines ~ mainFunctionCoveredLines,
            GcovJsonWriteOptions(gzip: true));

    const configPath = writeConfig(testEnv, "coverage_gcov.toml",
            coverageConfigText(format(`gcov_json = "%s"`, gcovJson)));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, configPath);
    assertImportedCoverageOutput(testRun.output);

    auto stat = coverageReportStat(testEnv);
    stat["killed"].integer.shouldBeGreaterThan(0);
}

@(testId ~ "shall merge duplicate line counts across multiple gcov json inputs")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const firstJson = (testEnv.outdir ~ "duplicate_first.gcov.json").toString;
    const secondJson = (testEnv.outdir ~ "duplicate_second.gcov.json").toString;
    writeGcovJson(firstJson, "program.cpp", coverFunctionCoveredLines,
            GcovJsonWriteOptions(includeCwd: false));
    writeGcovJson(secondJson, "program.cpp", withCount(coverFunctionCoveredLines, 0),
            GcovJsonWriteOptions(includeCwd: false));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", firstJson], ["--gcov-json", secondJson]]);
    assertImportedCoverageOutput(testRun.output, 2);

    auto coverage = loadCoverageView(testEnv, fixture);
    hasKnownStatus(coverage, 47, 54, true).shouldBeTrue;
}

@(testId ~ "shall warn about malformed gcov file entries and import the valid ones")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "malformed_entry.gcov.json").toString;
    JSONValue malformed;
    malformed["file"] = "program.cpp";
    malformed["lines"] = "not an array";
    writeGcovJsonFiles(gcovJson, [
        makeGcovFileData("program.cpp", coverFunctionCoveredLines, GcovJsonWriteOptions(
                includeCwd: false)),
        malformed
    ], GcovJsonWriteOptions(includeCwd: false));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]]);
    assertImportedCoverageOutput(testRun.output);
    testAnyOrder!SubStr([
        "Skipping malformed gcov file entry"
    ]).shouldBeIn(testRun.output);

    auto coverage = loadCoverageView(testEnv, fixture);
    hasKnownStatus(coverage, 47, 54, true).shouldBeTrue;
}

@(testId ~ "shall warn and fall back to built in coverage on bad gcov json")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "bad.gcov.json").toString;
    write(gcovJson, "{ definitely not valid json");

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]], false);
    testRun.success.shouldBeTrue;
    assertCoverageInstrumentationOutput(testRun.output);
    testAnyOrder!SubStr([
        "Failed to parse gcov json",
        "None of the gcov json files matched analyzed source files in the current work area."
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when gcov json is missing the files array")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "missing_files.gcov.json").toString;
    writeGcovJson(gcovJson, fixture.programCode, [],
            GcovJsonWriteOptions(includeFiles: false));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]], false);
    testRun.success.shouldBeTrue;
    assertCoverageInstrumentationOutput(testRun.output);
    testAnyOrder!SubStr([
        "Object 'files' not found in gcov json",
        "None of the gcov json files matched analyzed source files in the current work area."
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when gcov json files is not an array")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "files_not_array.gcov.json").toString;
    JSONValue root;
    root["files"] = "not an array";
    writeGcovJsonRoot(gcovJson, root, false);

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]], false);
    testRun.success.shouldBeTrue;
    assertCoverageInstrumentationOutput(testRun.output);
    testAnyOrder!SubStr([
        "Object 'files' in gcov json",
        "must be an array",
        "None of the gcov json files matched analyzed source files in the current work area."
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when coverage.gcov_json in toml cannot be parsed")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const configPath = writeConfig(testEnv, "bad_gcov_json_config.toml",
            coverageConfigText("gcov_json = [1]"));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, configPath, null, false);
    testRun.success.shouldBeTrue;
    assertBuiltInCoverageOutput(testRun.output);
    testAnyOrder!SubStr([
        "coverage.gcov_json: failed parsing"
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when coverage.gcov_json in toml is a scalar")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const configPath = writeConfig(testEnv, "scalar_gcov_json_config.toml",
            coverageConfigText("gcov_json = 1"));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, configPath, null, false);
    testRun.success.shouldBeTrue;
    assertBuiltInCoverageOutput(testRun.output);
    testAnyOrder!SubStr([
        "coverage.gcov_json: failed parsing"
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when gcov json input does not exist")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const missing = (testEnv.outdir ~ "missing.gcov.json.gz").toString;

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", missing]], false);
    testRun.success.shouldBeTrue;
    assertCoverageInstrumentationOutput(testRun.output);
    testAnyOrder!SubStr([
        "gcov json input does not exist",
        "No gcov json input files were found"
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when gcov json inputs are an empty directory and a wrong file type")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const emptyDir = (testEnv.outdir ~ "empty_coverage").toString;
    mkdirRecurse(emptyDir);
    const wrongFile = (testEnv.outdir ~ "not_gcov.json.txt").toString;
    write(wrongFile, "{}");

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig, [
        ["--gcov-json", emptyDir], ["--gcov-json", wrongFile]
    ], false);
    testRun.success.shouldBeTrue;
    assertCoverageInstrumentationOutput(testRun.output);
    testAnyOrder!SubStr([
        "No gcov json files found in",
        "gcov json input must end in .gcov.json or .gcov.json.gz",
        "No gcov json input files were found"
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when analyzed coverage regions are missing")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const noCoverageConfig = writeConfig(testEnv, "analyze_without_coverage.toml",
            analyzeWithoutCoverageConfigText);
    const gcovJson = (testEnv.outdir ~ "no_regions.gcov.json.gz").toString;
    writeGcovJson(gcovJson, fixture.programCode, coverFunctionCoveredLines[0 .. 3],
            GcovJsonWriteOptions(gzip: true));

    analyzeCoverageProgram(testEnv, fixture, noCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]], false);
    testRun.success.shouldBeTrue;
    assertCoverageInstrumentationOutput(testRun.output);
    testAnyOrder!SubStr([
        "No analyzed coverage regions found",
        "Re-run analyze with [coverage].use = true before importing gcov JSON"
    ]).shouldBeIn(testRun.output);
}

@(testId ~ "shall warn and fall back when gcov json does not match analyzed source files")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto fixture = setupCoverageFixture(testEnv);

    const gcovJson = (testEnv.outdir ~ "no_match.gcov.json").toString;
    writeGcovJson(gcovJson, "other.cpp", coverFunctionCoveredLines[0 .. 3],
            GcovJsonWriteOptions(includeCwd: false));

    analyzeCoverageProgram(testEnv, fixture, defaultCoverageConfig);

    auto testRun = runCoverageTest(testEnv, fixture, defaultCoverageConfig,
            [["--gcov-json", gcovJson]], false);
    testRun.success.shouldBeTrue;
    assertCoverageInstrumentationOutput(testRun.output);
    testAnyOrder!SubStr([
        "None of the gcov json files matched analyzed source files in the current work area."
    ]).shouldBeIn(testRun.output);
}
