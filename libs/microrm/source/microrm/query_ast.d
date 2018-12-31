/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MIT
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module contains an AST representation of a database query. The intention
is to encode the structure in the types so errors in the SQL statement are
detected at compile time.

# Grammar

The grammar is expressed in PEG form using the same terminology as the dub
package Pegged. It has not been verified to be correct so may contain errors.

This is simplified to only contain those parts of the grammar that is needed to
pretty print constructed SQL queries. It is not intended to be a grammar that
can correctly parse SQL. Thus it contains "blobs of data" that the grammar do
not care about. The important part is to keep the structure.  Where to insert
"blobs".

A secondary purpose is to give some compile time guarantees of the constructed
SQL queries. If it compiles it is reasonably assured to be correct.

When not necessary for pretty printing as a valid SQL blanks and such are
skipped in the grammar definition.

```sql
SQL         <- blank* Query (spacing / eoi)

Query       <- Select

Select      <- "SELECT" :blank+ ResultColumns :blank+ SelectOpt (Values :blank+)? Limit?
SelectOpt   <- From? Where? GroupBy? (Window :blank+)? OrderBy?

ResultColumns       <- ResultColumn ("," ResultColumn)*
ResultColumn        <- Star / ResultColumnExpr
ResultColumnExpr    <- Query / Blob

From    <- :blank+ "FROM" :blank+ (TableOrSubQueries / Blob)
Where   <- :blank+ "WHERE" :blank+ WhereExpr*
GroupBy <- :blank+ "GROUP BY" :blank+ Expr ("," Expr)* (:blank+ "HAVING" Expr)?
Window  <- Blob

WhereExpr   <- Expr (:blank+ WhereOp :blank+ Expr)?
WhereOp     <- "AND" / "OR"

Values  <- "VALUES" "(" Value ")" ("," "(" Value ")")*
Value   <- Expr ("," Expr)*

OrderBy         <- :blank+ "ORDER BY" :blank+ OrderingTerm ("," OrderingTerm)
OrderingTerm    <- Expr :blank+ OrderingTermSort?
OrderingTermSort <- "ASC" / "DESC" / ""

Limit <- "LIMIT" :blank+ (("OFFSET" :blank+ Expr) / ("," Expr))?

TableOrSubQueries       <- TableOrQuery ("," TableOrSubQuery)*
TableOrSubQuery         <- TableOrSubQuerySelect / ("(" TableOrSubQueries ")") / (TableRef Blob*) / Blob
TableOrSubQuerySelect   <- "(" Select ")" TableAlias?

# Reference an existing table
TableRef            <- SchemaName? TableName (:blank+ TableAlias)?

Expr        <- Blob

SchemaName  <- identifier "."
TableAlias  <- :blank+ "AS" :blank+ identifier
TableName   <- identifier
Star        <- "*"
# Not representable in the grammar because it can be anything without a formal
# terminator. Its purpose is to be an injection point of user data.
Blob        <- ""
```

## Grammar Encoding

 * `SumType` is used when possible.
 * `None` is the first member of a `SumType` when the node is optional.
 * Literals are used as is.
 * All nodes have a `toString`.
*/
module microrm.query_ast;

import std.array : empty;
import std.conv : to;
import std.format : formattedWrite, format;
import std.meta : AliasSeq;
import std.range.primitives : put, isOutputRange;
import std.traits : TemplateArgsOf;

import sumtype;

@safe:

//alias TableOrQuery = SumType!(TableName, Query);

/// A SQL statement.
struct Sql {
    Query query;
    alias query this;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        query.toString(w);
        put(w, ";");
    }

    string toString()() {
        import std.array : appender;

        auto app = appender!string();
        this.toString(app);
        return app.data;
    }
}

/** A SQL query.
 *
 * The differents between Sql and Query is that this may be nested in other nodes.
 */
struct Query {
    SumType!(Select) value;
    alias value this;

    static foreach (T; TemplateArgsOf!(typeof(value))) {
        this(T n) {
            value = typeof(value)(n);
        }
    }

    mixin ToStringSumType!value;
}

/// A Select statement.
struct Select {
    ResultColumn columns;
    /// Optional parts of the statement. At least one must in the end be active.
    SelectOpt opts;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        // TODO: add an assert that at least one of opts is not None.
        put(w, "SELECT ");
        columns.toString(w);
        put(w, " ");
        opts.toString(w);
    }
}

struct ResultColumns {
    ResultColumn required;
    ResultColumn[] optional;

    this(ResultColumn r, ResultColumn[] o = null) {
        required = r;
        optional = o;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        required.toString(w);
        foreach (v; optional) {
            put(w, ",");
            v.toString(w);
        }
    }
}

struct ResultColumn {
    SumType!(Star, ResultColumnExpr) value;
    mixin ToStringSumType!(value);
}

struct ResultColumnExpr {
    SumType!(Blob, Query*) value;
    mixin ToStringSumType!value;
}

struct SelectOpt {
    SumType!(None, From) from;
    SumType!(None, Where) where;
    //SumType!(None, Window) window_;
    SumType!(None, OrderBy) orderBy;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        from.match!((None v) {}, (From v) { v.toString(w); });
        where.match!((None v) {}, (Where v) { v.toString(w); });
        //window.match!((None v) {}, (Window v) { v.toString(w); });
        orderBy.match!((None v) {}, (OrderBy v) { v.toString(w); });
    }
}

struct From {
    SumType!(TableOrSubQueries, Blob) value;
    alias value this;
    mixin(makeCtor!(typeof(value))("value"));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, "FROM ");
        value.match!((TableOrSubQueries v) => v.toString(w), (Blob v) {
            v.toString(w);
        });
    }
}

struct Where {
    SumType!(None, WhereExpr) value;
    alias value this;
    mixin(makeCtor!(typeof(value))("value"));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        // TODO: should it quote strings?
        put(w, " WHERE ");
        value.match!((None v) {}, (WhereExpr v) => v.toString(w));
    }
}

struct WhereExpr {
    static struct Opt {
        WhereOp op;
        Expr expr;
    }

    Expr required;
    Opt[] optional;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        required.toString(w);
        foreach (v; optional) {
            put(w, " ");
            put(w, v.op.to!string);
            put(w, " ");
            v.expr.toString(w);
        }
    }
}

enum WhereOp {
    AND,
    OR
}

struct TableOrSubQueries {
    TableOrQuery required;
    TableOrQuery[] optional;

    ///
    this(TableOrQuery r, TableOrQuery[] o = null) @safe pure nothrow @nogc {
        required = r;
        optional = o;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        required.toString(w);
        foreach (v; optional) {
            put(w, ",");
            v.toString(w);
        }
    }
}

struct TableOrQuery {
    SumType!(TableOrSubQuerySelect*, TableOrSubQueries*, TableRef, Blob) value;
    alias value this;
    mixin(makeCtor!(typeof(value))("value"));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        value.match!((TableOrSubQuerySelect* v) { v.toString(w); }, (TableOrSubQueries* v) {
            put(w, "(");
            v.toString(w);
            put(w, ")");
        }, (TableRef v) { v.toString(w); }, (Blob v) { v.toString(w); });
    }
}

/// Reference to a table with options to reference another schema and/or create an alias.
struct TableRef {
    SumType!(None, SchemaName) schemaName;
    string tableName;
    SumType!(None, TableAlias) tableAlias;

    this(SchemaName schema, string name, TableAlias alias_) {
        schemaName = schema;
        tableName = name;
        tableAlias = alias_;
    }

    /// A ref to a table that rename it via an "AS" to `alias_`.
    this(string name, TableAlias alias_) {
        tableName = name;
        tableAlias = alias_;
    }

    /// A simple ref to a table.
    this(string tableName) {
        this.tableName = tableName;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        schemaName.match!((auto ref v) => v.toString(w));
        put(w, tableName);
        tableAlias.match!((auto ref v) => v.toString(w));
    }
}

struct TableOrSubQuerySelect {
    Select select;
    TableAlias alias_;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, "(");
        select.toString(w);
        put(w, ")");
        alias_.toString(w);
    }
}

struct TableAlias {
    string value;
    alias value this;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        if (value.empty)
            return;
        put(w, " AS ");
        put(w, value);
    }
}

struct OrderBy {
    OrderingTerm required;
    OrderingTerm[] optional;

    this(typeof(required) r, typeof(optional) o = null) @safe pure nothrow @nogc {
        required = r;
        optional = o;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, " ORDER BY ");
        required.toString(w);
        foreach (v; optional) {
            put(w, ",");
            v.toString(w);
        }
    }
}

struct OrderingTerm {
    SumType!(None, Blob) expr;
    SumType!(None, OrderingTermSort) sortTerm;

    mixin(makeCtor!(typeof(expr))("expr"));

    this(Blob expr, OrderingTermSort sortTerm) @safe pure nothrow @nogc {
        this.expr = expr;
        this.sortTerm = sortTerm;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        expr.match!((None n) {}, (Blob v) { v.toString(w); });
        sortTerm.match!((None n) {}, (OrderingTermSort v) {
            put(w, v.to!string);
        });
    }
}

enum OrderingTermSort {
    ASC,
    DESC,
}

struct SchemaName {
    string value;
    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, value);
        put(w, ".");
    }
}

struct Blob {
    string value;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, value);
    }
}

alias Expr = Blob;
alias None = Constant!(string.init);
alias Star = Constant!"*";
alias Window = Blob;

private:

/// Create a match that calls `.toString(w)` on all matches of the SumType.
mixin template ToStringSumType(alias member) {
    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        static string autoMatch(alias member)() {
            string rval = q{%s.match!(}.format(member.stringof);
            static foreach (T; TemplateArgsOf!(typeof(member))) {
                rval ~= q{(%s v) => v.toString(w),}.format(T.stringof);
            }
            rval ~= ");";
            return rval;
        }

        mixin(autoMatch!member);
    }
}

string makeBuild(ArgT, string member, string funcName)() {
    string rval = q{auto %s(%s v)}.format(funcName, ArgT.stringof);
    rval ~= "{";
    rval ~= member ~ " = v;";
    rval ~= q{return this;};
    rval ~= "}";
    return rval;
}

/// ctors for all template arguments of member.
string makeCtor(SumT)(string var) {
    string rval;
    static foreach (T; TemplateArgsOf!SumT) {
        rval ~= q{this(%1$s n) @safe pure nothrow {
            this.%2$s = n;
        }}.format(T.stringof, var);
        rval ~= "\n";
    }
    return rval;
}

/// Returns: a string that can be mixed in to create a setter for the member
mixin template makeBuilder(members...) {
    static string buildMember(alias member)() {
        enum memberStr = member.stringof;
        static assert(memberStr[$ - 1] == '_', "member must end with '_': " ~ memberStr);

        enum Type = typeof(member).stringof;
        string rval = q{auto %s(%s v)}.format(member.stringof[0 .. $ - 1], Type);
        rval ~= "{";
        rval ~= memberStr ~ " = v;";
        rval ~= q{return this;};
        rval ~= "}";
        return rval;
    }

    static foreach (member; members) {
        mixin(buildMember!member);
    }
}

/// A node representing a constant value.
struct Constant(string s) {
    string value = s;
    alias value this;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, value);
    }
}

version (unittest) {
    import unit_threaded.assertions : shouldEqual;
}

@("shall convert a query at compile time to SQL")
unittest {
    enum q = Select().Query.Sql.toString;
    q.shouldEqual("SELECT * ;");
}

@("shall convert a Select using From to SQL")
unittest {
    // arrange
    Select qblob, qtblRef, q;
    // act
    qblob.opts.from = Blob("foo").From;
    qtblRef.opts.from = TableOrSubQueries(TableOrQuery(TableRef("foo"))).From;
    // assert
    immutable expected = "SELECT * FROM foo;";
    foreach (s; [qblob, qtblRef])
        s.Query.Sql.toString.shouldEqual(expected);
}

@("shall convert a Select using a subquery in FROM to SQL")
unittest {
    // arrange
    Select qblob, qAlias, qRef, qsubBlob;
    // act
    qsubBlob.opts.from = Blob("foo I dance").From;
    qblob.opts.from = TableOrSubQueries(TableOrQuery(new TableOrSubQuerySelect(qsubBlob))).From;
    qAlias.opts.from = TableOrSubQueries(TableOrQuery(new TableOrSubQuerySelect(qsubBlob,
            TableAlias("bar")))).From;
    qRef.opts.from = TableOrSubQueries(TableOrQuery(new TableOrSubQueries(TableRef("foo")
            .TableOrQuery, [TableRef("smurf").TableOrQuery]))).From;
    // assert
    // a subquery as a blob that should be represented as-is.
    qblob.Query.Sql.toString.shouldEqual("SELECT * FROM (SELECT * FROM foo I dance);");
    // a subquery as a named select.
    qAlias.Query.Sql.toString.shouldEqual("SELECT * FROM (SELECT * FROM foo I dance) AS bar;");
    // multiple table refs.
    qRef.Query.Sql.toString.shouldEqual("SELECT * FROM (foo,smurf);");
}

@("shall convert a Select using an OrderBy to SQL")
unittest {
    // arrange
    Select q;
    q.opts.from = Blob("foo").From;
    // act
    q.opts.orderBy = OrderBy(OrderingTerm(Blob("bar")));
    // assert
    q.Query.Sql.toString.shouldEqual("SELECT * FROM foo ORDER BY bar;");
}

@("shall convert a Select using Where to SQL")
unittest {
    // arrange
    Select q;
    // act
    q.opts.from = Blob("foo").From;
    q.opts.where = WhereExpr(Expr("foo = bar"), [WhereExpr.Opt(WhereOp.OR,
            Expr("batman NOT NULL"))]).Where;
    // assert
    q.Query.Sql.toString.shouldEqual("SELECT * FROM foo WHERE foo = bar OR batman NOT NULL;");
}
