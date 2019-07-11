/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

partof: #SPC-llvm_hiwrap_debug-cfg_viewer

Manually tested to pass:
partof: #TST-llvm_hiwrap_debug_cfg_viewer_readfile

This file contains a simple program to view the CFG's for functions in a LLVM
IR bitcode file (.bc) or a c/c++ source file.
*/
module app;

import std.algorithm;
import std.format;
import std.getopt;
import std.path;
import std.stdio;
import std.typecons : Nullable;
import std.exception : collectException;
import std.process : execute;

int main(string[] args) {
    import std.array : array;
    import std.file : exists;
    import std.range : drop;

    bool help;
    bool view_cfg;
    bool view_cfg2;
    bool dump_cfg;
    bool dump_onlycfg;
    bool dump_ir_as_txt;
    string[] cflags;
    GetoptResult help_info;
    try {
        // dfmt off
        help_info = getopt(args, std.getopt.config.passThrough,
            std.getopt.config.keepEndOfOptions,
            "view-cfg", "View the CFG in GhostView", &view_cfg,
            "view-cfg2", "View the CFG kind 2", &view_cfg2,
            "dump-ir", "View the IR as text", &dump_ir_as_txt,
            "dump-cfg", "Dump the cfg to a file as plantuml", &dump_cfg,
            "dump-onlycfg", "Dump the cfg to a file as plantuml without the content of basic blocks", &dump_onlycfg,
            );
        // dfmt on
        help = help_info.helpWanted;
    }
    catch (Exception ex) {
        help = true;
    }

    void printHelp() {
        defaultGetoptPrinter(format("usage: %s FILE -- [CFLAGS]\n",
                args[0].baseName), help_info.options);
    }

    if (help) {
        printHelp;
        return 0;
    } else if (args.length <= 1) {
        writeln("Missing the required option FILE");
        printHelp;
        return 1;
    }

    cflags = args.find("--").drop(1).array();

    const auto infile = AbsolutePath(args[1]);
    if (!infile.exists) {
        writeln("File do not exist: ", infile);
        return 1;
    }

    const auto irfile = makeIRFile(infile, cflags);
    if (!irfile.hasValue) {
        writeln("Unable to read/undestand input: ", infile);
        return 1;
    }

    writeln("input LLVM IR: ", irfile.path);

    if (view_cfg)
        viewCFG(irfile);
    if (dump_ir_as_txt)
        viewIR(irfile);
    if (view_cfg2)
        viewCFG2(irfile);
    if (dump_cfg || dump_onlycfg)
        dumpCFG(irfile, dump_onlycfg);

    return 0;
}

struct AbsolutePath {
    this(string f) {
        this.path = f.absolutePath;
    }

    string path;
    alias path this;
}

struct IRFile {
    bool hasValue;
    AbsolutePath path;
    alias path this;
    private AbsolutePath tmpdir;
    private bool remove_tmpdir;

    @disable this(this);

    ~this() nothrow {
        import std.file : rmdirRecurse;

        if (remove_tmpdir) {
            try {
                rmdirRecurse(tmpdir);
            }
            catch (Exception e) {
                collectException(writeln("error: ", e.msg));
            }
        }
    }
}

IRFile makeIRFile(AbsolutePath p, string[] cflags) {
    import std.string : toStringz;

    if (p.extension == ".bc") {
        return IRFile(true, p);
    } else if (p.extension.among(".c", ".cxx", ".cpp")) {
        import core.sys.posix.stdlib : mkdtemp;

        char[] t = "cfg_viewer_XXXXXX".dup;
        mkdtemp(t.ptr);

        auto ir = AbsolutePath(buildPath(t, p.baseName.stripExtension ~ ".bc"));

        try {
            auto res = execute(["clang", "-emit-llvm", "-c", p, "-o", ir] ~ cflags);
            if (res.status != 0) {
                writeln(res.output);
                return IRFile();
            }

            writeln("creating temporary LLVM IR: ", ir);
            return IRFile(true, ir, AbsolutePath(t.idup), true);
        }
        catch (Exception e) {
            collectException(writeln("error: ", e.msg));
        }
    }

    return IRFile();
}

/**
 * partof: #TST-llvm_hiwrap_test_api_read_llvm_bc
 */
void viewCFG(ref const IRFile ir) {
    import llvm_hiwrap;

    auto ctx = Context.make;

    auto modres = File(ir.path).readModule(ctx, ir.path);
    if (!modres.isValid) {
        writeln("error: unable to create a LLVM IR module from input. Diagnostic:");
        writefln("%( %s%)", modres.diagnostic);
        return;
    }

    auto mod = modres.value;

    foreach (v; mod.functions) {
        llvm_hiwrap.viewCFG(v);
    }
}

void viewCFG2(ref const IRFile ir) {
    import std.conv;
    import std.range;
    import llvm_hiwrap;

    import llvm_hiwrap.ast.tree;

    struct MVisitor {
        alias Self = ModuleVisitor!MVisitor;
        size_t line;

        void visit(ref Module n, ref Self self) {
            writefln("ModuleID %s", n.identifier);
            accept(n, self);
        }

        void visit(ref FunctionValue n, ref Self self) {
            writefln("ID:%s name:%s BB:%s", n.asValue.id, n.asValue.name, n.countBasicBlocks);
            accept(n, self);
        }

        void visit(ref EntryBasicBlock n, ref Self self) {
            writefln("entryBlock ID:%s name:%s", n.asBasicBlock.id, n.asBasicBlock.name);
            line = 0;
            accept(n, self);
        }

        void visit(ref BasicBlock n, ref Self self) {
            writefln("ID:%s name:%s", n.id, n.name);
            line = 0;
            accept(n, self);
        }

        void visit(ref InstructionValue n, ref Self self) {
            writefln("%s %s: %s", line, n.opcode.to!string, n.asValue.spelling.toChar);
            line++;
        }
    }

    auto ctx = Context.make;

    auto modres = File(ir.path).readModule(ctx, ir.path);
    if (!modres.isValid) {
        writeln("error: unable to create a LLVM IR module from input. Diagnostic:");
        writefln("%( %s%)", modres.diagnostic);
        return;
    }

    auto mod = modres.value;

    ModuleVisitor!MVisitor visitor;
    visitor.visit(mod);
}

void viewIR(ref const IRFile ir) {
    import llvm_hiwrap;

    auto ctx = Context.make;

    auto modres = File(ir.path).readModule(ctx, ir.path);
    if (!modres.isValid) {
        writeln("error: unable to create a LLVM IR module from input. Diagnostic:");
        writefln("%( %s%)", modres.diagnostic);
        return;
    }

    auto mod = modres.value;
    writeln(mod.toString);
}

void dumpCFG(ref const IRFile ir, bool dump_onlycfg) {
    import std.array : Appender;
    import std.ascii;
    import std.conv;
    import std.range;
    import std.stdio;
    import std.format;
    import std.string;
    import std.typecons : NullableRef;
    import llvm_hiwrap;

    import llvm_hiwrap.ast.tree;

    struct BBLabel {
        private size_t nextId;
        private size_t[size_t] bbIdToGraphId;

        string make(BasicBlock bb) {
            if (auto result = bb.asValue.id in bbIdToGraphId)
                return (*result).to!string;

            bbIdToGraphId[bb.asValue.id] = nextId;
            auto result = nextId++;
            return result.to!string;
        }
    }

    /**
     * TODO because it uses baseName for the module it won't correctly work
     * with multiple modules with the same baseName but residing in different
     * directories.
     */
    struct MVisitor {
        alias Self = ModuleVisitor!MVisitor;
        import std.container : Array;

        this(File* f, bool dump_onlycfg) {
            app = f;
            no_bb_content = dump_onlycfg;
            bbLabel = BBLabel.init;
        }

        private bool no_bb_content;

        File* app;
        Array!string parents;

        // intermediate data for basic blocks when visiting a function.
        // required to avoid infinite loops because the graph is not a DAG.
        bool[size_t] visited_bbs;
        string last_block;

        BBLabel bbLabel;

        string lastParent() {
            return parents[$ - 1];
        }

        void pushParent(string p) {
            parents.insertBack(p);
        }

        void pushParent(const(char)[] p) {
            parents.insertBack(p.idup);
        }

        void popParent() {
            parents.removeBack;
        }

        void visit(ref Module n, ref Self self) {
            import std.path;

            pushParent(n.identifier.baseName);
            scope (exit)
                popParent;

            app.writeln("@startuml");
            app.writefln("[*] --> %s", lastParent);
            app.writefln("%s : Module", lastParent);
            accept(n, self);
            app.writeln("@enduml");
        }

        void visit(ref FunctionValue n, ref Self self) {
            auto parent = lastParent;
            auto me = n.asValue.name;
            pushParent(me);
            scope (exit)
                popParent;

            app.writefln("%s : Function", me);
            app.writefln("%s : BBs %s", me, n.countBasicBlocks);
            app.writefln("%s --> %s", parent, me);

            accept(n, self);
        }

        void visit(ref EntryBasicBlock n, ref Self self) {
            auto parent = lastParent;
            auto me = bbLabel.make(n.asBasicBlock).to!string;
            last_block = me;
            pushParent(me);
            scope (exit)
                popParent;

            app.writefln("%s : EntryBasicBlock", me);
            app.writefln("%s --> %s", parent, me);

            visited_bbs[n.asBasicBlock.id] = true;
            accept(n, self);

            if (last_block.length != 0)
                app.writefln("%s --> [*]", last_block);
        }

        void visit(ref BasicBlock n, ref Self self) {
            auto parent = lastParent;
            auto me = bbLabel.make(n).to!string;
            last_block = me;
            pushParent(me);
            scope (exit)
                popParent;

            app.writefln("%s --> %s", parent, me);

            if (n.id in visited_bbs) {
                return;
            }

            app.writefln("%s : BasicBlock", me);

            if (n.terminator.isNull || n.terminator.successors.length == 0) {
                last_block = null;
                app.writefln("%s --> [*]", me);
            }

            visited_bbs[n.id] = true;
            accept(n, self);
        }

        void visit(ref InstructionValue n, ref Self self) {
            if (no_bb_content)
                return;

            import std.algorithm : splitter;

            auto msg = n.asValue.spelling;
            foreach (l; msg.toChar.splitter(newline)) {
                app.writefln("%s : %s", lastParent, l);
            }
        }
    }

    auto ctx = Context.make;

    auto modres = File(ir.path).readModule(ctx, ir.path);
    if (!modres.isValid) {
        writeln("error: unable to create a LLVM IR module from input. Diagnostic:");
        writefln("%( %s%)", modres.diagnostic);
        return;
    }

    auto mod = modres.value;

    auto fout = File("dump.uml", "w");
    auto visitor = ModuleVisitor!(MVisitor)(MVisitor(&fout, dump_onlycfg));
    visitor.visit(mod);
}
