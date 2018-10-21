/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.nodes;

@safe:

struct Html {
    HtmlNode root;
    alias root this;

    HtmlNode preamble;
    HtmlNode head;
    HtmlNode preambleBody;
    HtmlNode body_;

    static auto make() {
        auto r = Html(new HtmlNode);

        r.preamble = r.n;
        r.n.put(`<html>`);

        r.head = r.n;
        r.n.put(`</head>`);

        r.preambleBody = r.n;

        r.body_ = r.n;
        r.n.put(`</body>`);

        r.n.put(`</html>`);

        return r;
    }

    string toString() @safe {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) {
        root.toString(w);
    }
}

class HtmlNode {
    import std.array : Appender;
    import std.range.primitives : isInputRange;

    HtmlNode[] nodes;

    Appender!(string[]) lines;
    alias lines this;

    Appender!(string[2][]) attrs;

    /// automatically write a newline after each line
    bool autoNewline = true;

    /// Tag to use to open/close.
    string tag;

    /// Create and return a new node
    HtmlNode n() {
        auto n_ = new HtmlNode;
        put(n_);
        return n_;
    }

    HtmlNode n(string tag) {
        auto n_ = new HtmlNode;
        n_.tag = tag;
        put(n_);
        return n_;
    }

    HtmlNode put(HtmlNode n) {
        nodes ~= n;
        return n;
    }

    HtmlNode put(string l) {
        lines.put(l);
        return this;
    }

    HtmlNode put(RangeT)(RangeT r) if (isInputRange!RangeT) {
        foreach (l; r)
            lines.put(l);
        return this;
    }

    HtmlNode putAttr(string key, string val) {
        string[2] s = [key, val];
        attrs.put(s);
        return this;
    }

    override string toString() @safe {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) {
        import std.format : formattedWrite;
        import std.range : put;

        if (tag.length != 0) {
            if (attrs.data.length != 0) {
                formattedWrite(w, "<%s", tag);
                foreach (t; attrs.data)
                    formattedWrite(w, ` %s="%s"`, t[0], t[1]);
                put(w, ">");
            } else
                formattedWrite(w, "<%s>", tag);
            if (autoNewline)
                put(w, "\n");
        }

        foreach (l; lines.data) {
            put(w, l);
            if (autoNewline)
                put(w, "\n");
        }

        foreach (n; nodes)
            n.toString(w);

        if (tag.length != 0) {
            formattedWrite(w, "</%s>", tag);
            if (autoNewline)
                put(w, "\n");
        }
    }
}

Html defaultHtml(string title) {
    import std.format;
    import std.xml : encode;

    auto h = Html.make;
    h.preamble.put(`<!DOCTYPE html>`);
    h.head.put(`<head>`);
    h.head.put(`<meta http-equiv="Content-Type" content="text/html;charset=UTF-8">`);
    h.head.put(format(`<title>%s</title>`, title.encode));
    h.preambleBody.put(`<style>body {font-family: monospace; font-size: 14px;}</style>`);
    h.body_.put(`<body>`);

    return h;
}

/// Create a href link.
HtmlNode aHref(T)(T link, string desc) {
    import std.format : format;
    import std.xml : encode;

    auto n = new HtmlNode;
    n.put(format(`<a href="%s">%s</a>`, link, desc.encode));
    return n;
}
