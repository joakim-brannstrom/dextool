/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsrcgen.sh;

import std.typecons : Yes, Flag;

import dsrcgen.base;

version (Have_unit_threaded) {
    import unit_threaded : shouldEqual;
} else {
    /// Fallback when unit_threaded doon't exist.
    private void shouldEqual(T0, T1)(T0 value, T1 expect) {
        assert(value == expect, value);
    }
}

@safe:

/** A sh comment using '#' as is.
 *
 * Compared to Text a comment is affected by indentation.
 */
class Comment : BaseModule {
    mixin Attrs;

    private string contents;

    /// Construct a one-liner comment from contents.
    this(string contents) {
        this.contents = contents;
    }

    override string renderIndent(int parent_level, int level) {
        if ("begin" in attrs) {
            return indent(attrs["begin"] ~ contents, parent_level, level);
        }

        return indent("# " ~ contents, parent_level, level);
    }
}

/** A sh statement.
 *
 * Affected by attribute end.
 * stmt ~ end
 *    <recursive>
 */
class Stmt(T) : T {
    private string headline;

    ///
    this(string headline) {
        this.headline = headline;
    }

    /// See_Also: BaseModule
    override string renderIndent(int parent_level, int level) {
        auto end = "end" in attrs;
        string r = headline ~ (end is null ? "" : *end);

        if ("noindent" !in attrs) {
            r = indent(r, parent_level, level);
        }

        return r;
    }
}

/** A shell block wrapped by default in '{}'.
 *
 * Affected by attribute begin, end, noindent.
 * headline ~ begin
 *     <recursive>
 * end
 * noindent affects post_recursive. If set no indention there.
 * r.length > 0 catches the case when begin or end is empty string. Used in switch/case.
 */
class Suite(T) : T {
    private string headline;

    ///
    this(string headline) {
        this.headline = headline;
    }

    override string renderIndent(int parent_level, int level) {
        import std.ascii : newline;

        string r;
        if (auto begin = "begin" in attrs) {
            r = headline ~ *begin;
        } else {
            r = headline ~ " {" ~ newline;
        }

        if (r.length > 0 && "noindent" !in attrs) {
            r = indent(r, parent_level, level);
        }
        return r;
    }

    override string renderPostRecursive(int parent_level, int level) {
        string r = "}";
        if (auto end = "end" in attrs) {
            r = *end;
        }

        if (r.length > 0 && "noindent" !in attrs) {
            r = indent(r, parent_level, level);
        }
        return r;
    }
}

class ShModule : BaseModule {
    mixin Attrs;

    /** Access to self.
     *
     * Useful in with-statements.
     */
    auto _() {
        return this;
    }

    /** An empty node holdig other nodes.
     *
     * Not affected by indentation.
     */
    auto empty() {
        auto e = new Empty!(typeof(this));
        append(e);
        return e;
    }

    /** Make a Comment followed by a separator.
     *
     * Affected by indentation.
     *
     * TODO should have an addSep like stmt have.
     */
    Comment comment(string comment) {
        auto e = new Comment(comment);
        e.sep;
        append(e);
        return e;
    }

    /** Make a raw Text.
     *
     * Note it is intentional that the text object do NOT have a separator. It
     * is to allow detailed "surgical" insertion of raw text/data when no
     * semantical "helpers" exist for a specific use case.
     */
    auto text(string content) pure {
        auto e = new Text!(typeof(this))(content);
        append(e);
        return e;
    }

    /** A basic building block with no content.
     *
     * Useful when a "node" is needed to add further content in.
     * The node is affected by indentation.
     */
    auto base() {
        auto e = new typeof(this);
        append(e);
        return e;
    }

    /** Make a statement with an optional separator.
     *
     * A statement is commonly an individual item or at the most a line.
     *
     * Params:
     *   stmt_ = raw text to use as the statement
     *   separator = flag determining if a separator is added
     *
     * Returns: Stmt instance stored in this.
     */
    auto stmt(string stmt_, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Stmt!(typeof(this))(stmt_);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    /** Make a suite/block as a child of "this" with an optional separator.
     *
     * The separator is inserted after the block.
     *
     * Returns: Suite instance stored in this.
     */
    auto suite(string headline, Flag!"addSep" separator = Yes.addSep) {
        auto e = new Suite!(typeof(this))(headline);
        append(e);
        if (separator) {
            sep();
        }
        return e;
    }

    // === Statements ===
    auto shebang(string s) {
        auto e = text("#!" ~ s);
        sep();
        return e;
    }

    // === Suites ===
}

/** Generate a shell script with shebang
 */
struct ShScriptModule {
    /// Shell root.
    ShModule doc;
    /// Shebang at the top.
    ShModule shebang;
    /// Shell content
    ShModule content;

    /// Make a sh-script
    static auto make() {
        ShScriptModule m;
        m.doc = new ShModule;
        m.doc.suppressIndent(1);

        m.shebang = m.doc.base;
        m.shebang.suppressIndent(1);

        m.content = m.doc.base;
        m.content.suppressIndent(1);

        return m;
    }

    auto render() {
        return doc.render();
    }
}

@("Shall be a comment")
unittest {
    auto m = new ShModule;
    m.comment("a comment");

    m.render.shouldEqual("    # a comment
");
}

@("Shall be a sh statement")
unittest {
    auto m = new ShModule;
    m.stmt("echo");

    m.render.shouldEqual("    echo
");
}

@("Shall be a sh block")
unittest {
    auto m = new ShModule;

    with (m.suite("for")) {
        stmt("echo");
    }

    m.render.shouldEqual("    for {
        echo
    }
");
}

@("Shall be a shell script")
unittest {
    auto sh = ShScriptModule.make();

    sh.shebang.shebang("/bin/sh");
    sh.content.stmt("echo");

    sh.render.shouldEqual("#!/bin/sh
echo
");
}
