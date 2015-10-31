/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.analyzer;

import std.ascii;
import std.array;
import std.conv;
import std.stdio;
import std.string;
import std.typecons;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Compiler;
import clang.Cursor;
import clang.Index;
import clang.Token;
import clang.TranslationUnit;
import clang.Visitor;

import dsrcgen.cpp;

import translator.Type;

/** Visit all nodes in a Clang AST to call apply on the nodes.
 * The functions incr() and decr() are infered at compile time.
 * The function incr() is called when entering a new level in the AST and decr() is called when leaving.
 * The return value from apply() determines if visit_ast will decend into that node.
 *
 * Params:
 *  cursor = Top cursor to traverse from.
 *  v = User context to apply on the nodes in the AST.
 * Example:
 * ---
 * visit_ast!TranslateContext(cursor, this);
 * ---
 */
void visitAst(VisitorType)(ref Cursor cursor, ref VisitorType v) {
    import std.traits;

    static if (__traits(hasMember, VisitorType, "incr")) {
        v.incr();
    }
    bool decend = v.apply(cursor);

    if (!cursor.isEmpty && decend) {
        foreach (child, parent; Visitor(cursor)) {
            visitAst(child, v);
        }
    }

    static if (__traits(hasMember, VisitorType, "decr")) {
        v.decr();
    }
}

void logNode(int line = __LINE__, string file = __FILE__,
    string funcName = __FUNCTION__, string prettyFuncName = __PRETTY_FUNCTION__,
    string moduleName = __MODULE__)(ref Cursor c, int level) {
    auto indent_str = new char[level * 2];
    foreach (ref ch; indent_str)
        ch = ' ';

    logger.logf!(line, file, funcName, prettyFuncName, moduleName)(
        logger.LogLevel.trace, "%s|%s [d=%s %s %s line=%d, col=%d %s]",
        indent_str, c.spelling, c.displayName, c.kind, c.type,
        c.location.spelling.line, c.location.spelling.column, c.abilities);
}

/// Keep track of the depth in the AST.
struct VisitNodeDepth {
public:
    /// Increment the AST depth.
    void incr() {
        level++;
    }

    /// Pop the stack if depth matches depth of top element of stack.
    void decr() {
        level--;
    }

    /// Return: AST depth when traversing.
    @property auto depth() {
        return level;
    }

private:
    int level;
}

/** Stack useful when visiting the AST.
 * Could be used to know what node to attach code in.
 * Params:
 *  Tmodule = object type to build the stack of
 * Example:
 * ---
 * mixin VisitNodeModule!CppModule;
 * CppModule node;
 * push(node);
 * current.sep();
 * ---
 */
struct VisitNodeModule(Tmodule) {
public:
    /// Increment the AST depth.
    void incr() {
        level++;
    }

    /// Pop the stack if depth matches depth of top element of stack.
    void decr() {
        stack.pop(level);
        level--;
    }

    /// Return: AST depth when traversing.
    @property auto depth() {
        return level;
    }

    @property auto current() {
        return stack.top;
    }

    /** Push an element to the stack together with current AST depth.
     * Params:
     *  c = Element to push
     *
     * Return: Pushed element.
     */
    auto push(T)(T c) {
        return stack.push(level, cast(Tmodule) c);
    }

private:
    alias StackType = IdStack!(int, Tmodule);
    StackType stack;
    int level;
}

/** Stack with a discrete id that is only popped when the id matches top of stack.
 * If the stack is empty then Tvalue.init is returned from current.
 *
 * TODO add a contract that invariant stack_id.length == stack_value.length
 *
 * Keeping two stacks and in sync for easier access to the full stack of values.
 * Useful when the stack of values is transformed to other data structures.
 * Example
 * ---
 * import std.array : join;
 * IdStack!(int, string) ns;
 * ns.push(0, "std");
 * ns.push(1, "BaseClass");
 * writeln(join(ns.values, "::"));
 * ---
 * output: std::BaseClass
 *
 * Example:
 * ---
 * IdStack!(int, int) s;
 * s.push(2, 0);
 * s.push(5, 1);
 * s.push(7, 5);
 * for (int i = 8; i != 0; --i) {
 *    s.pop(i);
 *    write(s.current, " ");
 * }
 * ---
 * output: 7 7 7 5 5 5 5 2 0
 */
struct IdStack(Tid, Tvalue) {
    import std.typecons : NullableRef;

    ref auto push(Tid id, Tvalue c) {
        stack_id ~= id;
        stack_value ~= c;
        return stack_value[$ - 1];
    }

    /** Pop from stack all items that have a matching id.
     */
    void pop(Tid id) {
        while (stack_value.length > 0 && stack_id[$ - 1] == id) {
            stack_value.length = stack_value.length - 1;
            stack_id.length = stack_id.length - 1;
        }
    }

    @property auto top() {
        NullableRef!Tvalue r;
        if (stack_value.length > 0)
            r.bind(&stack_value[$ - 1]);
        return r;
    }

    @property auto size() {
        return stack_value.length;
    }

    @property const ref auto values() {
        return stack_value;
    }

private:
    Tid[] stack_id;
    Tvalue[] stack_value;
}
