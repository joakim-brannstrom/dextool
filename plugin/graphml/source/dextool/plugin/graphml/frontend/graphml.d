/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Analyze C/C++ source code to generate a GraphML of the relations.
*/
module dextool.plugin.frontend.graphml;

import std.typecons : Flag;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type;

import dextool.plugin.types;
import dextool.plugin.graphml.backend : Controller, Parameters, Products;
import dextool.plugin.graphml.frontend.argsparser;

class GraphMLFrontend : Controller, Parameters, Products {
    import std.typecons : Tuple;
    import std.regex : regex, Regex;
    import dextool.type : FileName, DirName;

    private {
        static struct FileData {
            FileName filename;
            string data;
        }

        static enum fileExt = ".graphml";

        immutable Flag!"genClassMethod" gen_class_method;
        immutable Flag!"genClassParamDependency" gen_class_param_dep;
        immutable Flag!"genClassInheritDependency" gen_class_inherit_dep;
        immutable Flag!"genClassMemberDependency" gen_class_member_dep;

        immutable FilePrefix file_prefix;
        immutable DirName output_dir;

        Regex!char[] exclude;
        Regex!char[] restrict;
    }

    immutable FileName toFile;

    /// Data produced by the generatore intented to be written to specified file.
    FileData[] fileData;

    static auto makeVariant(ref RawConfiguration parsed) {
        import std.algorithm : map;
        import std.array : array;

        Regex!char[] exclude = parsed.fileExclude.map!(a => regex(a)).array();
        Regex!char[] restrict = parsed.fileRestrict.map!(a => regex(a)).array();

        auto gen_class_method = cast(Flag!"genClassMethod") parsed.classMethod;
        auto gen_class_param_dep = cast(Flag!"genClassParamDependency") parsed.classParamDep;
        auto gen_class_inherit_dep = cast(Flag!"genClassInheritDependency") parsed.classInheritDep;
        auto gen_class_member_dep = cast(Flag!"genClassMemberDependency") parsed.classMemberDep;

        auto variant = new GraphMLFrontend(FilePrefix(parsed.filePrefix), DirName(parsed.out_),
                gen_class_method, gen_class_param_dep, gen_class_inherit_dep,
                gen_class_member_dep);

        variant.exclude = exclude;
        variant.restrict = restrict;

        return variant;
    }

    this(FilePrefix file_prefix, DirName output_dir, Flag!"genClassMethod" class_method,
            Flag!"genClassParamDependency" class_param_dep,
            Flag!"genClassInheritDependency" class_inherit_dep,
            Flag!"genClassMemberDependency" class_member_dep) {

        this.file_prefix = file_prefix;
        this.output_dir = output_dir;
        this.gen_class_method = class_method;
        this.gen_class_param_dep = class_param_dep;
        this.gen_class_inherit_dep = class_inherit_dep;
        this.gen_class_member_dep = class_member_dep;

        import std.path : baseName, buildPath, relativePath, stripExtension;

        this.toFile = FileName(buildPath(cast(string) output_dir,
                cast(string) file_prefix ~ "raw" ~ fileExt));
    }

    // -- Products --

    override void put(FileName fname, const(char)[] content) {
    }
}

@safe struct XmlStream {
    import dextool.type : FileName;
    import std.stdio : File;

    private File fout;

    static auto make(FileName fname) {
        auto fout = File(cast(string) fname, "w");
        return XmlStream(fout);
    }

    @disable this(this);

    void put(const(char)[] v) {
        fout.write(v);
    }
}

unittest {
    import std.range.primitives : isOutputRange;

    static assert(isOutputRange!(XmlStream, char), "Should be an output range");
}

struct Lookup {
    import cpptooling.data.symbol : Container, USRType;
    import cpptooling.data : Location, LocationTag, TypeKind;

    private Container* container;

    auto kind(USRType usr) @safe {
        return container.find!TypeKind(usr);
    }

    auto location(USRType usr) @safe {
        return container.find!LocationTag(usr);
    }
}

/// TODO cleaner split between frontend and backend is needed. Move most of the
/// logic to the backend and leave the error handling in the frontend. E.g. by
/// using callbacks.
ExitStatusType pluginMain(GraphMLFrontend variant, const string[] in_cflags,
        CompileCommandDB compile_db, InFiles in_files, Flag!"skipFileError" skipFileError) {
    import std.algorithm : map;
    import std.conv : text;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.range : enumerate;
    import std.typecons : TypedefType, Yes, NullableRef;

    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.symbol : Container;
    import cpptooling.utility.virtualfilesystem : vfsFileName = FileName,
        vfsMode = Mode;
    import dextool.plugin.graphml.backend : GraphMLAnalyzer,
        TransformToXmlStream;
    import dextool.utility : prependDefaultFlags, PreferLang, analyzeFile;

    const auto user_cflags = prependDefaultFlags(in_cflags, PreferLang.none);

    Container container;
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    auto xml_stream = XmlStream.make(variant.toFile);

    auto transform_to_file = new TransformToXmlStream!(XmlStream, Lookup)(xml_stream,
            Lookup(&container));

    auto visitor = new GraphMLAnalyzer!(typeof(transform_to_file))(transform_to_file,
            variant, variant, variant, container);

    ExitStatusType analyze(T, U)(ref T in_file, U idx, U total_files) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        string[] use_cflags;
        AbsolutePath abs_in_file;

        if (compile_db.length > 0) {
            auto db_search_result = compile_db.appendOrError(user_cflags, in_file);
            if (db_search_result.isNull) {
                return ExitStatusType.Errors;
            }
            use_cflags = db_search_result.get.cflags;
            abs_in_file = db_search_result.get.absoluteFile;
        } else {
            use_cflags = user_cflags.dup;
            abs_in_file = AbsolutePath(FileName(in_file));
        }

        if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        return ExitStatusType.Ok;
    }

    ExitStatusType analyzeFiles(T)(ref T files, const size_t total_files, ref string[] skipped_files) {

        foreach (idx, file; files) {
            auto status = analyze(file, idx, total_files);
            if (status == ExitStatusType.Errors && skipFileError) {
                skipped_files ~= file;
            } else if (status == ExitStatusType.Errors) {
                return ExitStatusType.Errors;
            }
        }

        return ExitStatusType.Ok;
    }

    import dextool.plugin.graphml.backend : xmlHeader, xmlFooter;

    string[] skipped_files;
    ExitStatusType exit_status;

    auto stream = NullableRef!XmlStream(&xml_stream);
    xmlHeader(stream);
    scope (success)
        xmlFooter(stream);

    if (in_files.length == 0) {
        auto range = compile_db.map!(a => a.absoluteFile).enumerate;
        exit_status = analyzeFiles(range, compile_db.length, skipped_files);
    } else {
        auto range = cast(TypedefType!InFiles) in_files;
        exit_status = analyzeFiles(range, in_files.length, skipped_files);
    }

    transform_to_file.finalize();

    if (skipped_files.length != 0) {
        logger.error("Skipped the following files due to errors:");
        foreach (f; skipped_files) {
            logger.error("  ", f);
        }
    }

    debug {
        logger.trace(visitor);
    }

    return exit_status;
}
