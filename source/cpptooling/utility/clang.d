// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.utility.clang;

import std.traits : ReturnType;

import clang.Cursor;
import clang.Visitor : Visitor;

/** Traverses a clang AST.
 * Required functions of VisitorType:
 *   void applyRoot(ref Cursor root). Called with the root node.
 *   bool apply(ref Cursor child, ref Cursor parent). Called for all nodes under root.
 * Optional functions:
 *   void incr(). Called before descending a node.
 *   void decr(). Called after ascending a node.
 */
void visitAst(VisitorT)(ref Cursor cursor, ref VisitorT v)
        if (hasApply!VisitorT && hasApplyRoot!VisitorT) {
    enum NodeType {
        Root,
        Child
    }

    static void helperVisitAst(NodeType NodeT)(ref Cursor child, ref Cursor parent, ref VisitorT v) {
        static if (__traits(hasMember, VisitorT, "incr")) {
            v.incr();
        }

        bool descend;

        // Root has no parent.
        static if (NodeT == NodeType.Root) {
            v.applyRoot(child);
            descend = true;
        } else {
            descend = v.apply(child, parent);
        }

        if (!child.isEmpty && descend) {
            foreach (child_, parent_; Visitor(child)) {
                helperVisitAst!(NodeType.Child)(child_, parent_, v);
            }
        }

        static if (__traits(hasMember, VisitorT, "decr")) {
            v.decr();
        }
    }

    helperVisitAst!(NodeType.Root)(cursor, cursor, v);
}

void logNode(ref Cursor c, in int indent = 0, string func = __FUNCTION__, uint line = __LINE__) {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.Cursor : dump;
    import clang.info;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent).array();
        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d %s%s|%s|%s|%s:%d:%d [%s:%d]",
             indent,
             indent_,
             dump(c),
             c.displayName,
             c.abilities,
             c.location.file,
             c.location.spelling.line,
             c.location.spelling.column,
             func,
             line);
    }
    // dfmt on
}

private:
enum hasApply(T) = __traits(hasMember, T, "apply") && is(ReturnType!(T.apply) == bool);
enum hasApplyRoot(T) = __traits(hasMember, T, "applyRoot") && is(ReturnType!(T.applyRoot) == void);
