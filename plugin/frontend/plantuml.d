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

import std.typecons : Flag, Yes, No;

import logger = std.experimental.logger;

import application.types;
import application.utility;

import plugin.types;
import plugin.backend.plantuml : Controller, Parameters, Products;
import cpptooling.data.representation : CppRoot, CppNamespace, CppClass;
import application.compilation_db;

/** Contains the file processing directives after parsing user arguments.
 *
 * If no --in argument then it is assumed that all files in the CompileDB
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

    auto parsed = docopt.docoptParse(cast(TypedefType!CliOption) opt,
            cast(TypedefType!CliArgs) args);

    string[] cflags;
    if (parsed["--"].isTrue) {
        cflags = parsed["CFLAGS"].asList;
    }

    import plugin.docopt_util;

    printArgs(parsed);

    auto variant = PlantUMLFrontend.makeVariant(parsed);

    CompileCommandDB compile_db;
    if (!parsed["--compile-db"].isEmpty) {
        compile_db = parsed["--compile-db"].asList.fromArgCompileDb;
    }

    FileProcess file_process;
    if (parsed["--in"].isEmpty) {
        file_process = FileProcess.make;
    } else {
        //TODO part of the multi file handling
        file_process = FileProcess.make(FileName(parsed["--in"].asList[0]));
    }

    auto skipFileError = cast(Flag!"skipFileError") parsed["--skip-file-error"].isTrue;

    return genUml(variant, cflags, compile_db, file_process, skipFileError);
}

// dfmt off
static auto plantuml_opt = CliOptionParts(
    "usage:
 dextool uml [options] [--compile-db=...] [--file-exclude=...] [--in=...] [--] [CFLAGS...]
 dextool uml [options] [--compile-db=...] [--file-restrict=...] [--in=...] [--] [CFLAGS...]",
    // -------------
    " --out=dir           directory for generated files [default: ./]
 --file-prefix=p     Prefix used when generating test artifacts [default: view_]
 --class-method      Include methods in the generated class diagram
 --class-paramdep    Class method parameters as directed association in diagram
 --class-inheritdep  Class inheritance in diagram
 --class-memberdep   Class member as composition/aggregation in diagram
 --comp-by-file      Components by file instead of directory
 --comp-strip=r      Regex used to strip path used to derive component name
 --gen-style-incl    Generate a style file and include in all diagrams
 --gen-dot           Generate a dot graph block in the plantuml output
 --skip-file-error   Skip files that result in compile errors (only when using compile-db and processing all files)",
    // -------------
"others:
 --in=              Input files to parse
 --compile-db=j      Retrieve compilation parameters from the file
 --file-exclude=     Exclude files from generation matching the regex
 --file-restrict=    Restrict the scope of the test double to those files
                     matching the regex
"
);
// dfmt on

/** Frontend for PlantUML generator.
 *
 * TODO implement --in=... for multi-file handling
 */
class PlantUMLFrontend : Controller, Parameters, Products {
    import std.string : toLower;
    import std.regex : regex, Regex;
    import std.typecons : Tuple, Flag, Yes, No;
    import application.types : FileName, DirName, FilePrefix;
    import application.utility;

    import docopt : ArgValue;
    import dsrcgen.plantuml;

    alias FileData = Tuple!(FileName, "filename", string, "data");

    static const fileExt = ".pu";
    static const inclExt = ".iuml";

    // TODO ugly hack to remove immutable. Fix it appropriately
    FileNames input_files;
    immutable DirName output_dir;
    immutable FileName file_classes;
    immutable FileName file_components;
    immutable FileName file_style;
    immutable FileName file_style_output;

    immutable FilePrefix file_prefix;

    immutable Flag!"genClassMethod" gen_class_method;
    immutable Flag!"genClassParamDependency" gen_class_param_dep;
    immutable Flag!"genClassInheritDependency" gen_class_inherit_dep;
    immutable Flag!"genClassMemberDependency" gen_class_member_dep;
    immutable Flag!"doStyleIncl" do_style_incl;
    immutable Flag!"doGenDot" do_gen_dot;
    immutable Flag!"doComponentByFile" do_comp_by_file;

    Regex!char[] exclude;
    Regex!char[] restrict;
    Regex!char comp_strip;

    /// Data produced by the generator intended to be written to specified file.
    FileData[] fileData;

    static auto makeVariant(ref ArgValue[string] parsed) {
        import std.algorithm : map;
        import std.array : array;

        Regex!char[] exclude = parsed["--file-exclude"].asList.map!(a => regex(a)).array();
        Regex!char[] restrict = parsed["--file-restrict"].asList.map!(a => regex(a)).array();
        Regex!char comp_strip;

        if (!parsed["--comp-strip"].isNull) {
            string strip_user = parsed["--comp-strip"].toString;
            comp_strip = regex(strip_user);
            logger.trace("User supplied regex via --comp-strip: ", strip_user);
        }

        auto gen_class_method = cast(Flag!"genClassMethod") parsed["--class-method"].isTrue;
        auto gen_class_param_dep = cast(Flag!"genClassParamDependency") parsed["--class-paramdep"]
            .isTrue;
        auto gen_class_inherit_dep = cast(Flag!"genClassInheritDependency") parsed[
        "--class-inheritdep"].isTrue;
        auto gen_class_member_dep = cast(Flag!"genClassMemberDependency") parsed[
        "--class-memberdep"].isTrue;

        auto gen_style_incl = cast(Flag!"doStyleIncl") parsed["--gen-style-incl"].isTrue;
        auto gen_dot = cast(Flag!"doGenDot") parsed["--gen-dot"].isTrue;
        auto do_comp_by_file = cast(Flag!"doComponentByFile") parsed["--comp-by-file"].isTrue;

        auto variant = new PlantUMLFrontend(FilePrefix(parsed["--file-prefix"].toString),
                DirName(parsed["--out"].toString), gen_style_incl,
                gen_dot, gen_class_method, gen_class_param_dep,
                gen_class_inherit_dep, gen_class_member_dep, do_comp_by_file);

        variant.exclude = exclude;
        variant.restrict = restrict;
        variant.comp_strip = comp_strip;

        return variant;
    }

    this(FilePrefix file_prefix, DirName output_dir, Flag!"doStyleIncl" style_incl,
            Flag!"doGenDot" gen_dot, Flag!"genClassMethod" class_method,
            Flag!"genClassParamDependency" class_param_dep, Flag!"genClassInheritDependency" class_inherit_dep,
            Flag!"genClassMemberDependency" class_member_dep,
            Flag!"doComponentByFile" do_comp_by_file) {
        this.file_prefix = file_prefix;
        this.output_dir = output_dir;
        this.gen_class_method = class_method;
        this.gen_class_param_dep = class_param_dep;
        this.gen_class_inherit_dep = class_inherit_dep;
        this.gen_class_member_dep = class_member_dep;
        this.do_comp_by_file = do_comp_by_file;
        this.do_gen_dot = gen_dot;
        this.do_style_incl = style_incl;

        import std.path : baseName, buildPath, relativePath, stripExtension;

        this.file_classes = FileName(buildPath(cast(string) output_dir,
                cast(string) file_prefix ~ "classes" ~ fileExt));
        this.file_components = FileName(buildPath(cast(string) output_dir,
                cast(string) file_prefix ~ "components" ~ fileExt));
        this.file_style_output = FileName(buildPath(cast(string) output_dir,
                cast(string) file_prefix ~ "style" ~ inclExt));
        this.file_style = FileName(relativePath(cast(string) file_prefix ~ "style" ~ inclExt,
                cast(string) output_dir));
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

    Flag!"genStyleInclFile" genStyleInclFile() {
        import std.path : exists;

        return cast(Flag!"genStyleInclFile")(do_style_incl && !exists(cast(string) file_style));
    }

    FileName doComponentNameStrip(FileName fname) {
        import std.path : dirName;
        import application.utility : stripFile;

        if (do_comp_by_file) {
            return stripFile(fname, comp_strip);
        } else {
            return stripFile(FileName((cast(string) fname).dirName), comp_strip);
        }
    }

    // -- Parameters --

    DirName getOutputDirectory() const {
        return output_dir;
    }

    Parameters.Files getFiles() const {
        return Parameters.Files(file_classes, file_components, file_style, file_style_output);
    }

    FilePrefix getFilePrefix() const {
        return file_prefix;
    }

    Flag!"genClassMethod" genClassMethod() const {
        return gen_class_method;
    }

    Flag!"genClassParamDependency" genClassParamDependency() const {
        return gen_class_param_dep;
    }

    Flag!"genClassInheritDependency" genClassInheritDependency() const {
        return gen_class_inherit_dep;
    }

    Flag!"genClassMemberDependency" genClassMemberDependency() const {
        return gen_class_member_dep;
    }

    Flag!"doStyleIncl" doStyleIncl() const {
        return do_style_incl;
    }

    Flag!"doGenDot" doGenDot() const {
        return do_gen_dot;
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

struct Lookup {
    import cpptooling.analyzer.kind : TypeKind;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.data.type : Location, LocationTag;

    private Container* container;

    auto kind(USRType usr) @safe {
        return container.find!TypeKind(usr);
    }

    auto location(USRType usr) @safe {
        return container.find!LocationTag(usr);
    }
}

ExitStatusType genUml(PlantUMLFrontend variant, string[] in_cflags,
        CompileCommandDB compile_db, FileProcess file_process, Flag!"skipFileError" skipFileError) {
    import std.algorithm : map, joiner;
    import std.conv : text;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : TypedefType, Yes;
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    import cpptooling.analyzer.clang.context : ClangContext;
    import plugin.backend.plantuml : Generator, UMLVisitor, UMLClassDiagram,
        UMLComponentDiagram, TransformToDiagram;

    Container container;
    auto generator = Generator(variant, variant, variant);

    // note how the transform is connected with destinations via the generator
    // uml diagrams
    auto transform = new TransformToDiagram!(Controller, Parameters, Lookup)(variant,
            variant, Lookup(&container), generator.umlComponent, generator.umlClass);

    auto visitor = new UMLVisitor!(Controller, typeof(transform))(variant, transform, container);
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    final switch (file_process.directive) {
    case FileProcess.Directive.All:
        const auto cflags = prependDefaultFlags(in_cflags, "");
        CompileCommand.AbsoluteFileName[] unable_to_parse;

        const auto total_files = compile_db.length;
        logger.trace("Number of files to process: ", total_files);

        foreach (idx, entry; (cast(TypedefType!CompileCommandDB) compile_db)) {
            logger.infof("File %d/%d ", idx + 1, total_files);
            auto entry_cflags = cflags ~ parseFlag(entry);

            auto analyze_status = analyzeFile(cast(string) entry.absoluteFile,
                    entry_cflags, visitor, ctx);

            // compile error, let user decide how to proceed.
            if (analyze_status == ExitStatusType.Errors && skipFileError) {
                logger.errorf("Continue analyze...");
                unable_to_parse ~= entry.absoluteFile;
            } else if (analyze_status == ExitStatusType.Errors) {
                return ExitStatusType.Errors;
            }
        }

        if (unable_to_parse.length > 0) {
            // TODO be aware that no test exist for this logic
            import std.ascii : newline;
            import std.range : roundRobin, repeat;

            logger.errorf("Compile errors in the following files:\n%s\n",
                    unable_to_parse.map!(a => (cast(string) a))
                    .roundRobin(newline.repeat(unable_to_parse.length)).joiner().text);
        }
        break;

    case FileProcess.Directive.Single:
        const auto user_cflags = prependDefaultFlags(in_cflags, "");

        string[] use_cflags;
        string abs_in_file;
        string input_file = cast(string) file_process.inputFile;

        logger.trace("Input file: ", input_file);

        if (compile_db.length > 0) {
            auto db_search_result = compile_db.appendOrError(user_cflags, input_file);
            if (db_search_result.isNull) {
                return ExitStatusType.Errors;
            }
            use_cflags = db_search_result.get.cflags;
            abs_in_file = db_search_result.get.absoluteFile;
        } else {
            use_cflags = user_cflags.dup;
            abs_in_file = buildNormalizedPath(input_file).asAbsolutePath.text;
        }

        if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }
        break;
    }

    transform.finalize();
    generator.process();

    debug {
        logger.trace(container.toString);
        logger.trace(generator.umlComponent.toString);
        logger.trace(generator.umlClass.toString);
    }

    return writeFileData(variant.fileData);
}
