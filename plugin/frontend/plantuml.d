// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Generate PlantUML diagrams of C/C++ source code.
*/
module plugin.frontend.plantuml;

import logger = std.experimental.logger;

import application.types;
import application.utility;

import plugin.types;
import plugin.backend.plantuml : Controller, Parameters, Products;
import cpptooling.data.representation : CppRoot;
import application.compilation_db;

/** Contains the file processing directives after parsing user arguments.
 *
 * If not FILE argument then it is assumed that all files in the CompileDB
 * shall be processed.
 *
 * Indicated by the directive All.
 */
struct FileProcess {
    enum Directive {
        Single,
        All
    }

    static auto make() {
        return FileProcess(Directive.All, FileName(null));
    }

    static auto make(FileName input_file) {
        return FileProcess(Directive.Single, input_file);
    }

    Directive directive;
    FileName inputFile;
}

auto runPlugin(CliOption opt, CliArgs args) {
    import std.typecons : TypedefType;
    import docopt;
    import argvalue;

    auto parsed = docopt.docopt(cast(TypedefType!CliOption) opt, cast(TypedefType!CliArgs) args);

    string[] cflags;
    if (parsed["--"].isTrue) {
        cflags = parsed["CFLAGS"].asList;
    }

    import plugin.docopt_util;

    printArgs(parsed);

    auto variant = PlantUMLFrontend.makeVariant(parsed);

    CompileCommandDB compile_db;
    if (!parsed["--compile-db"].isNull) {
        compile_db = parsed["--compile-db"].toString.orDefaultDb.fromFile;
    }

    FileProcess file_process;
    if (parsed["FILE"].isNull) {
        file_process = FileProcess.make;
    } else {
        file_process = FileProcess.make(FileName(parsed["FILE"].toString));
    }

    return genUml(variant, cflags, compile_db, file_process);
}

// dfmt off
static auto plantuml_opt = CliOptionParts(
    "usage:
 dextool uml [options] [--file-exclude=...] [FILE] [--] [CFLAGS...]
 dextool uml [options] [--file-restrict=...] [FILE] [--] [CFLAGS...]",
    // -------------
    " --out=dir           directory for generated files [default: ./]
 --compile-db=j     Retrieve compilation parameters from the file
 --file-prefix=p     prefix used when generating test artifacts [default: view_]
 --class-methods     include methods in the generated class diagram",
    // -------------
"others:
 --file-exclude=     exclude files from generation matching the regex.
 --file-restrict=    restrict the scope of the test double to those files
                     matching the regex.
"
);
// dfmt on

/** Frontend for PlantUML generator
 */
class PlantUMLFrontend : Controller, Parameters, Products {
    import std.string : toLower;
    import std.regex : regex, Regex;
    import std.typecons : Tuple, Flag, Yes, No;
    import application.types : FileName, DirName, FilePrefix;
    import application.utility;

    import argvalue; // from docopt
    import dsrcgen.plantuml;

    alias FileData = Tuple!(FileName, "filename", string, "data");

    static const fileExt = ".pu";

    // TODO ugly hack to remove immutable. Fix it appropriately
    FileName input_file;
    immutable DirName output_dir;
    immutable FileName file_component;

    immutable FilePrefix file_prefix;

    immutable Flag!"generateClassMethods" gen_class_methods;

    Regex!char[] exclude;
    Regex!char[] restrict;

    /// Data produced by the generator intended to be written to specified file.
    FileData[] fileData;

    static auto makeVariant(ref ArgValue[string] parsed) {
        import std.algorithm : map;
        import std.array : array;

        Regex!char[] exclude = parsed["--file-exclude"].asList.map!(a => regex(a)).array();
        Regex!char[] restrict = parsed["--file-restrict"].asList.map!(a => regex(a)).array();
        Regex!char strip_incl;

        auto class_methods = parsed["--class-methods"].isTrue
            ? Yes.generateClassMethods : No.generateClassMethods;

        auto variant = new PlantUMLFrontend(FilePrefix(parsed["--file-prefix"].toString),
                DirName(parsed["--out"].toString), class_methods);

        variant.exclude = exclude;
        variant.restrict = restrict;

        return variant;
    }

    this(FilePrefix file_prefix, DirName output_dir, Flag!"generateClassMethods" gen_class_methods) {
        this.file_prefix = file_prefix;
        this.output_dir = output_dir;
        this.gen_class_methods = gen_class_methods;

        import std.path : baseName, buildPath, stripExtension;

        this.file_component = FileName(buildPath(cast(string) output_dir,
                cast(string) file_prefix ~ "classes" ~ fileExt));
    }

    // -- Controller --

    bool doFile(in string filename, in string info) {
        import std.algorithm : canFind;
        import std.regex : matchFirst;

        bool r = true;

        // docopt blocks during parsing so both restrict and exclude cannot be
        // set at the same time.
        if (restrict.length > 0) {
            r = canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(restrict);
            debug {
                logger.tracef(!r, "--file-restrict skipping %s", info);
            }
        } else if (exclude.length > 0) {
            r = !canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(exclude);
            debug {
                logger.tracef(!r, "--file-exclude skipping %s", info);
            }
        }

        return r;
    }

    bool doClassMethods() const {
        return gen_class_methods;
    }

    // -- Parameters --

    DirName getOutputDirectory() {
        return output_dir;
    }

    Parameters.Files getFiles() {
        return Parameters.Files(file_component);
    }

    FilePrefix getFilePrefix() {
        return file_prefix;
    }

    // -- Products --

    void putFile(FileName fname, PlantumlRootModule root) {
        fileData ~= FileData(fname, root.render());
    }

    void putFile(FileName fname, PlantumlModule pm) {
        fileData ~= FileData(fname, pm.render());
    }

    void putLocation(FileName fname, LocationType type) {
    }
}

ExitStatusType genUml(PlantUMLFrontend variant, string[] in_cflags,
        CompileCommandDB compile_db, FileProcess file_process) {
    import std.conv : text;
    import std.file : exists;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import cpptooling.analyzer.clang.context;
    import cpptooling.analyzer.clang.visitor;
    import cpptooling.data.symbol.container;
    import plugin.backend.plantuml : Generator;

    auto cflags = prependLangFlagIfMissing(in_cflags, "-xc++");
    Container symbol_container;
    Nullable!CppRoot root;

    final switch (file_process.directive) {
    case FileProcess.Directive.All:
        break;

    case FileProcess.Directive.Single:
        //TODO refactor when All is finished. This is a special case of All.
        auto input_file = buildNormalizedPath(
                cast(string) file_process.inputFile).asAbsolutePath.text;
        logger.trace("Input file: ", input_file);

        cflags = compile_db.appendIfFound(cflags, input_file);

        analyzeFile(input_file, cflags, symbol_container, root);

        if (root.isNull) {
            return ExitStatusType.Errors;
        }
        break;
    }

    // process and put the data in variant.
    Generator(variant, variant, variant).process(root.get, symbol_container);

    return writeFileData(variant.fileData);
}
