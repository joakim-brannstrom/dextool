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

    auto skipFileError = parsed["--skip-file-error"].isTrue ? Yes.skipFileError : No.skipFileError;

    return genUml(variant, cflags, compile_db, file_process, skipFileError);
}

// dfmt off
static auto plantuml_opt = CliOptionParts(
    "usage:
 dextool uml [options] [--file-exclude=...] [FILE] [--] [CFLAGS...]
 dextool uml [options] [--file-restrict=...] [FILE] [--] [CFLAGS...]",
    // -------------
    " --out=dir           directory for generated files [default: ./]
 --compile-db=j      Retrieve compilation parameters from the file
 --file-prefix=p     prefix used when generating test artifacts [default: view_]
 --class-methods     include methods in the generated class diagram
 --skip-file-error   Skip files that result in compile errors (only when using compile-db and processing all files)",
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

/** Merge the content of two Representations.
 *
 * Incomplete merge so far, only classes.
 *
 * Assuming that it is a merge of namespace and their content that is needed.
 * The content of classes etc do not change.
 */
auto merge(T)(T ra, T rb) if (is(T == CppRoot)) {
    import std.algorithm : each, filter;
    import std.range : chain, tee;

    import cpptooling.data.symbol.types;

    logger.trace("root");
    logger.trace("Merge A ", ra.toString);
    logger.trace("Merge B ", rb.toString);

    T r;

    logger.tracef("(%d %d) (%d %d)", ra.namespaceRange.length,
            ra.classRange.length, rb.namespaceRange.length, rb.classRange.length);

    {
        logger.trace(" -- class merge --");
        CppClass[FullyQualifiedNameType] merged;

        foreach (c; chain(ra.classRange, rb.classRange)) {
            auto fqn = c.fullyQualifiedName;
            if (fqn in merged) {
                logger.trace("merge ", fqn, "|", merged.keys);
                merged[fqn] = mergeClass(merged[fqn], c);
            } else {
                merged[fqn] = c;
            }
        }

        foreach (c; merged.values) {
            r.put(c);
        }

        logger.trace(merged.keys);
        logger.trace("Merged ", merged.length);
    }

    {
        logger.trace(" -- namespace merge --");
        CppNamespace[FullyQualifiedNameType] merged;

        foreach (ns; chain(ra.namespaceRange, rb.namespaceRange)) {
            auto fqn = ns.fullyQualifiedName;

            if (fqn in merged) {
                logger.trace("merge ", fqn, "|", merged.keys);
                merged[fqn] = mergeNamespace(merged[fqn], ns);
            } else {
                merged[fqn] = ns;
            }
        }

        foreach (ns; merged.values) {
            r.put(ns);
        }

        logger.trace(merged.keys);
        logger.trace("Merged ", merged.length);
    }

    assert(r.namespaceRange.length <= (ra.namespaceRange.length + rb.namespaceRange.length));
    assert(r.classRange.length <= (ra.classRange.length + rb.classRange.length));

    return r;
}

CppNamespace mergeNamespace(T)(T ra, T rb) if (is(T == CppNamespace)) {
    import std.algorithm : each, filter;
    import std.range : chain, tee;

    import cpptooling.data.symbol.types;

    logger.trace("ns");
    //logger.trace("Merge A ", ra.toString);
    //logger.trace("Merge B ", rb.toString);

    auto r = T(ra.resideInNs);

    logger.tracef("(%d %d) (%d %d)", ra.namespaceRange.length,
            ra.classRange.length, rb.namespaceRange.length, rb.classRange.length);

    {
        logger.trace(" -- class merge --");
        CppClass[FullyQualifiedNameType] merged;

        foreach (c; chain(ra.classRange, rb.classRange)) {
            auto fqn = c.fullyQualifiedName;
            if (fqn in merged) {
                logger.trace("merge ", fqn, "|", merged.keys);
                merged[fqn] = mergeClass(merged[fqn], c);
            } else {
                merged[fqn] = c;
            }
        }

        foreach (c; merged.values) {
            r.put(c);
        }

        logger.trace(merged.keys);
        logger.trace("Merged ", merged.length);
    }

    {
        logger.trace(" -- namespace merge --");
        CppNamespace[FullyQualifiedNameType] merged;

        foreach (ns; chain(ra.namespaceRange, rb.namespaceRange)) {
            auto fqn = ns.fullyQualifiedName;

            if (fqn in merged) {
                logger.trace("merge ", fqn, "|", merged.keys);
                merged[fqn] = mergeNamespace(merged[fqn], ns);
            } else {
                merged[fqn] = ns;
            }
        }

        foreach (ns; merged.values) {
            r.put(ns);
        }

        logger.trace(merged.keys);
        logger.trace("Merged ", merged.length);
    }

    assert(r.namespaceRange.length <= (ra.namespaceRange.length + rb.namespaceRange.length));
    assert(r.classRange.length <= (ra.classRange.length + rb.classRange.length));

    return r;
}

auto mergeClass(T)(T ca, T cb) {
    import std.algorithm;
    import cpptooling.data.representation : AccessType, CppVariable;

    static string internalToString(CppClass.CppFunc f) {
        import std.variant : visit;
        import cpptooling.data.representation;

        // dfmt off
        return f.visit!((CppMethod a) => a.toString,
                        (CppMethodOp a) => a.toString,
                        (CppCtor a) => a.toString,
                        (CppDtor a) => a.toString);
        // dfmt on
    }

    auto r = CppClass(ca);

    {
        bool[string] methods;
        ca.methodRange.each!(a => methods[a.toString] = true);
        foreach (m; cb.methodPublicRange.filter!(a => internalToString(a) !in methods)) {
            r.put(m);
            methods[internalToString(m)] = true;
        }
        logger.trace(r.toString);
    }

    {
        bool[CppVariable] members;
        ca.memberRange.each!((a) { members[a.name] = true; });
        logger.trace(members);
        foreach (m; cb.memberRange.filter!(a => a.name !in members)) {
            logger.trace(m.name);
            r.put(m, AccessType.Public);
            members[m.name] = true;
        }
        logger.trace(members);
        logger.trace(r.toString);
    }

    return r;
}

ExitStatusType genUml(PlantUMLFrontend variant, string[] in_cflags,
        CompileCommandDB compile_db, FileProcess file_process, Flag!"skipFileError" skipFileError) {
    import std.algorithm : map;
    import std.conv : text;
    import std.file : exists;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : TypedefType;

    import cpptooling.analyzer.clang.context;
    import cpptooling.analyzer.clang.visitor;
    import cpptooling.data.symbol.container;
    import plugin.backend.plantuml : Generator;

    final switch (file_process.directive) {
    case FileProcess.Directive.All:
        auto cflags = prependLangFlagIfMissing(in_cflags, "-xc++");
        Container symbol_container;
        CppRoot root;

        logger.trace("Number of files to process: ", compile_db.length);

        foreach (entry; (cast(TypedefType!CompileCommandDB) compile_db)) {
            logger.trace("Input file: ", cast(string) entry.absoluteFile);
            auto entry_cflags = cflags ~ parseFlag(entry);

            Nullable!CppRoot partial_root;
            analyzeFile(cast(string) entry.absoluteFile, entry_cflags,
                    symbol_container, partial_root);

            // compile error, let user decide how to proceed.
            if (partial_root.isNull && skipFileError) {
                logger.errorf("Continue analyze...");
            } else if (partial_root.isNull) {
                return ExitStatusType.Errors;
            } else {
                root = merge(root, partial_root);
            }
        }

        // process and put the data in variant.
        Generator(variant, variant, variant).process(root, symbol_container);
        break;

    case FileProcess.Directive.Single:
        auto cflags = prependLangFlagIfMissing(in_cflags, "-xc++");

        //TODO refactor when All is finished. This is a special case of All.
        auto input_file = buildNormalizedPath(cast(string) file_process.inputFile)
            .asAbsolutePath.text;
        logger.trace("Input file: ", input_file);

        cflags = compile_db.appendIfFound(cflags, input_file);

        Container symbol_container;
        Nullable!CppRoot root;
        analyzeFile(input_file, cflags, symbol_container, root);

        if (root.isNull) {
            return ExitStatusType.Errors;
        }

        // process and put the data in variant.
        Generator(variant, variant, variant).process(root.get, symbol_container);
        break;
    }

    return writeFileData(variant.fileData);
}
