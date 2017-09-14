/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains an example plugin that demonstrate how to:
 - interact with the clang AST
 - print the AST nodes when debugging is activated by the user via the command line
 - find all free functions and generate a dummy implementation.

It is purely intended as an example to get started developing **your** plugin.
*/

module dextool.plugin.runner;

import std.stdio;
import logger = std.experimental.logger;

import dextool.type : ExitStatusType, FileName, AbsolutePath;

/** _main_ plugin function.

Called by the generic main function.

See plugin/source/dextool/plugin/main/standard.d for how the optional main
function work and what it requires.

As can be seen in standard.d, args are the program arguments.
It is up to the plugin for further interpretation.
*/
ExitStatusType runPlugin(string[] args) {
    RawConfiguration pargs;
    pargs.parse(args);

    // the dextool plugin architecture requires that two lines are printed upon
    // request by the main function.
    //  - a name of the plugin.
    //  - a oneliner description.
    if (pargs.shortPluginHelp) {
        writeln("example");
        writeln("print all AST nodes of some c/c++ source code");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.file.length == 0) {
        writeln("Missing file --in");
        return ExitStatusType.Errors;
    }

    writeln("Run the plugin -d to see the AST");

    import dextool.utility : prependDefaultFlags, PreferLang;

    const auto cflags = prependDefaultFlags(pargs.cflags, PreferLang.cpp);

    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context : ClangContext;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto visitor = new TUVisitor;

    import dextool.utility : analyzeFile;

    auto exit_status = analyzeFile(AbsolutePath(FileName(pargs.file)), cflags, visitor, ctx);

    if (exit_status == ExitStatusType.Ok) {
        writeln(visitor.generatedCode.render);
    }

    return exit_status;
}

/** Handle parsing of user arguments.

For a simple plugin this is overly complex. But a plugin very seldom stays
simple. By keeping the user input parsing and validation separate from the rest
of the program it become more robust to future changes.
*/
struct RawConfiguration {
    import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;

    bool shortPluginHelp;
    bool help;
    string file;
    string[] cflags;

    private GetoptResult help_info;

    void parse(string[] args) {
        static import std.getopt;

        try {
            // dfmt off
            help_info = getopt(args, std.getopt.config.keepEndOfOptions,
                   "short-plugin-help", "short description of the plugin",  &shortPluginHelp,
                   "in", "Input file to parse", &file);
            // dfmt on
            help = help_info.helpWanted;
        }
        catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    void printHelp() {
        import std.stdio : writeln;

        defaultGetoptPrinter("Usage: dextool example [options] [--in=] [-- CFLAGS...]",
                help_info.options);
    }
}

import cpptooling.analyzer.clang.ast : Visitor;

/** A basic visitor showing all the main categories of nodes.

# AST Traversal
The visitor logic of the AST is structured in node groups via dynamic dipatch.
See the Visitor class for the implementation details

To catch all Statements it is enough to implement, as in this example, an
override for the Statement node.

But this isn't always desired.
To separate the node WhileStmt from the group Statement it is enough to
implement the following override:
---
override void visit(const WhileStmt) {...}
---
*/
final class TUVisitor : Visitor {
    import cpptooling.analyzer.clang.ast;
    import cpptooling.data.symbol : Container;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dsrcgen.cpp;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    CppHModule generatedCode;
    private CppModule generatedFunctions;
    private Container container;

    this() {
        this.generatedCode = CppHModule("a_ifdef_guard");
        this.generatedFunctions = generatedCode.content.base;

        generatedCode.header.comment("A file header");
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.clang.analyze_helper;
        import cpptooling.data;

        // the purpose of dsrcgen is to get a semens of semantic equivalence
        // between the statements and expressions in D and the then resulting
        // C++ code.

        auto res = analyzeFunctionDecl(v, container, indent + 1);
        if (res.isValid && !res.isVariadic) {
            // .func_body generate a body. D's with-statement makes all
            // operations inside the with-stmt to operate on the object
            // returned from func_body.
            with (generatedFunctions.func_body(res.returnType.toStringDecl(""),
                    res.name, res.params.joinParams)) {
                // example of creating a vector
                stmt(Et("std::vector")("int") ~ E("x"));

                // a function must return something when the return value isn't
                // void.
                if (res.returnType.kind.info.kind == TypeKind.Info.Kind.primitive
                        && res.returnType.toStringDecl("") != "void") {
                    // try to instantiate and return a value of the return type
                    return_(E(res.returnType.toStringDecl(""))(""));
                }
            }
        }

        v.accept(this);
    }

    override void visit(const(Directive) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Preprocessor) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Reference) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }
}
