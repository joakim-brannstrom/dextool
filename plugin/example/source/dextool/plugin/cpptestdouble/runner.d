/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains an example plugin that prints the AST to the console when
debugging is activated by the user.
It is purely intended as an example to get started developing **your** plugin.
*/

module dextool.plugin.runner;

import std.stdio;
import logger = std.experimental.logger;

import dextool.type : ExitStatusType;

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

    import dextool.utility : prependDefaultFlags;

    const auto cflags = prependDefaultFlags(pargs.cflags, "-xc++");

    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context : ClangContext;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto visitor = new TUVisitor;

    import dextool.utility : analyzeFile;

    return analyzeFile(pargs.file, cflags, visitor, ctx);
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
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

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
