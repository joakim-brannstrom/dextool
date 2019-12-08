#!/usr/bin/env dub
/+ dub.sdl:
    name "pandoc"
+/
/** This script produces a PDF of the requirements, design and test
 * documentation for the Dextool mutation testing plugin.
 *
 * Dependent on the following packages (Ubuntu):
 * `sudo apt install texlive-bibtex-extra biber pandoc pandoc-citeproc texlive-font-utils latexmk texlive-fonts-extra`
 */
import core.stdc.stdlib;
import logger = std.experimental.logger;
import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.exception : collectException;
import std.file;
import std.path;
import std.process;
import std.range;
import std.stdio;
import std.string;

void main(string[] args) {
    const string root = getcwd();

    const latex_dir = buildPath(root, "latex");
    if (!exists(latex_dir)) {
        mkdir(latex_dir);
    }

    prepareFigures(buildPath(root, "design", "figures"), buildPath(latex_dir, "figures"));

    chdir(latex_dir);
    scope (exit)
        chdir(root);

    const metadata = buildPath(root, "metadata.yaml");
    const latex_template = buildPath(root, "default.latex");
    const biblio = buildPath(root, "references.bib");
    const output = "dextool_srs_sdd_svc";

    auto dat = Pandoc(metadata, latex_template, biblio);

    string[] chapters = [
        "use_cases.md", "purpose.md", "security.md", "architecture.md",
        "mutations.md", "analyzer/analyzer.md", "test_mutant/basis.md",
        "test_mutant/pull_request.md", "test_mutant/tracker.md",
        "usability/sanity_check.md", "usability/report.md", "future_work.md",
    ];

    pandoc(dat, chain(chapters.map!(a => buildPath(root, "design", a)),
            [
                "definitions.md", "abbrevations.md", "appendix.md",
                "references.md"
            ].map!(a => buildPath(root, a))).array, output);
}

struct Pandoc {
    string metadata;
    string latexTemplate;
    string biblio;
}

void pandoc(Pandoc dat, string[] files, const string output) {
    const outputTex = output ~ ".tex";
    const biblio = buildPath(output.dirName, dat.biblio.baseName);
    copy(dat.biblio, biblio);

    // dfmt off
    auto cmd = ["pandoc",
         //"--pdf-engine", "xelatex",
         "--template", dat.latexTemplate,
         "-f", "markdown+smart+pipe_tables+raw_html+fenced_code_blocks+auto_identifiers+gfm_auto_identifiers+backtick_code_blocks+autolink_bare_uris+space_in_atx_header+strikeout+shortcut_reference_links+angle_brackets_escapable+lists_without_preceding_blankline+citations+yaml_metadata_block+tex_math_dollars+raw_tex+footnotes+header_attributes+link_attributes",
         "-t", "latex",
         "--listings",
         "--standalone",
         "--toc",
         "--bibliography", biblio,
         //"--biblio", dat.biblio,
         //"--biblatex", "-M", "biblio-style=numeric-comp",
         //"--csl", "chicago-author-date.csl",
         "--natbib", "-M", "biblio-style=unsrtnat", "-M", "biblio-title=heading=none",
         "-o", outputTex,
         dat.metadata,
    ] ~ files;
    // dfmt on

    run(cmd);
    run(["pdflatex", outputTex]);
    run(["bibtex", outputTex.setExtension("aux")]).collectException;
    run(["pdflatex", outputTex]);
    run(["pdflatex", outputTex]);
}

void prepareFigures(string src, string dest_dir) {
    import std.algorithm : map, joiner;
    import std.datetime : SysTime, Clock;
    import std.file : timeLastModified, setTimes;
    static import std.process;

    if (!exists(dest_dir))
        mkdirRecurse(dest_dir);

    foreach (f; dirEntries(src, SpanMode.shallow).filter!(a => a.extension.among(".pu", ".uml"))) {
        const dst = buildPath(dest_dir, f.name.baseName);
        if (f.timeLastModified < timeLastModified(dst, SysTime.min)) {
            writefln("%s not modified thus skipping to update the image", f);
            continue;
        }

        writefln("Generating image %s -> %s", f, dst.setExtension("eps"));
        copy(f.name, dst);
        setTimes(dst, Clock.currTime, Clock.currTime);
        try {
            spawnProcess(["plantuml", "-teps", dst], null, std.process.Config.none, dest_dir).wait;
        } catch (Exception e) {
            logger.warning(e.msg);
        }
    }
}

auto run(string[] cmd) {
    writeln("run: ", cmd.joiner(" "));
    auto res = execute(cmd);
    writeln(res.output);

    if (res.status != 0)
        throw new Exception("Command failed");

    return res;
}
