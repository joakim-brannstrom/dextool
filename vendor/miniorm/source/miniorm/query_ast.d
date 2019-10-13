/**
Copyright: Copyright (c) 2018-2019, Joakim Brännström. All rights reserved.
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

# --- SELECT START ---
Select      <- "SELECT" :blank+ ResultColumns :blank+ From? Where? GroupBy? (Window :blank+)? OrderBy? Values? Limit?

ResultColumns       <- ResultColumn ("," ResultColumn)*
ResultColumn        <- Star / ResultColumnExpr
ResultColumnExpr    <- Query / Blob

From    <- :blank+ "FROM" :blank+ (TableOrSubQueries / Blob)
Where   <- :blank+ "WHERE" :blank+ WhereExpr*
GroupBy <- :blank+ "GROUP BY" :blank+ Expr ("," Expr)* (:blank+ "HAVING" Expr)?
Window  <- Blob

WhereExpr   <- Expr (:blank+ WhereOp :blank+ Expr)?
WhereOp     <- "AND" / "OR"

OrderBy         <- :blank+ "ORDER BY" :blank+ OrderingTerm ("," OrderingTerm)
OrderingTerm    <- Expr :blank+ OrderingTermSort?
OrderingTermSort <- "ASC" / "DESC" / ""

Limit <- "LIMIT" :blank+ Expr :blank+ (("OFFSET" :blank+ Expr) / ("," Expr))?

TableOrSubQueries       <- TableOrQuery ("," TableOrSubQuery)*
TableOrSubQuery         <- TableOrSubQuerySelect / ("(" TableOrSubQueries ")") / (TableRef Blob*) / Blob
TableOrSubQuerySelect   <- "(" Select ")" TableAlias?

# --- SELECT END ---

# --- INSERT START ---
Insert          <- InsertOpt :blank+ "INTO" :blank+ TableRef TableAlias? InsertColumns? InsertValues
InsertOpt       <- "INSERT" / "REPLACE" / "INSERT OR REPLACE" / "INSERT OR ROLLBACK" / "INSERT OR ABORT" / "INSERT OR FAIL" / "INSERT OR IGNORE"
InsertColumns    <- :blank+ "(" ColumnName ("," ColumnName)* ")"
InsertValues    <- :blank+ (Values / Select / "DEFAULT VALUES")
ColumnName      <- identifier

# --- INSERT END ---

# --- DELETE START ---
Delete          <- "DELETE FROM" :blank+ TableRef Where?
# --- DELETE END ---

# Reference an existing table
TableRef            <- SchemaName? TableName TableAlias?

Values  <- :blank+ "VALUES" "(" Value ")" ("(" Value ")")*
Value   <- Expr ("," Expr)*

TableAlias  <- :blank+ "AS" :blank+ identifier

Expr        <- Blob
# Not representable in the grammar because it can be anything without a formal
# terminator. Its purpose is to be an injection point of user data.
Blob        <- ""

SchemaName  <- identifier "."
TableName   <- identifier
Star        <- "*"
```

## Grammar Encoding

 * `SumType` is used when possible.
 * `None` is the first member of a `SumType` when the node is optional.
 * Literals are used as is.
 * All nodes have a `toString`.
*/
module miniorm.query_ast;

import std.array : empty;
import std.conv : to;
import std.format : formattedWrite, format;
import std.meta : AliasSeq;
import std.range.primitives : put, isOutputRange;
import std.traits : TemplateArgsOf;

import sumtype;

@safe:

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
    SumType!(Select, Insert, Delete) value;
    alias value this;

    static foreach (T; TemplateArgsOf!(typeof(value))) {
        this(T n) {
            value = typeof(value)(n);
        }
    }

    mixin ToStringSumType!value;
}

// #########################################################################
/// # Select START
// #########################################################################

/// A Select statement.
struct Select {
    ResultColumns columns;

    /// Optional parts of the statement. At least one must in the end be active.
    SumType!(None, From) from;
    SumType!(None, Where) where;
    //SumType!(None, Window) window_;
    SumType!(None, OrderBy) orderBy;
    SumType!(None, Limit) limit;

    mixin(makeAssign!(typeof(this))([
                "columns", "from", "where", "orderBy", "limit"
            ]));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, "SELECT ");
        columns.toString(w);

        put(w, " ");

        // TODO: add an assert that at least one of opts is not None?
        from.match!((None v) {}, (From v) { v.toString(w); });
        where.match!((None v) {}, (Where v) { v.toString(w); });
        //window.match!((None v) {}, (Window v) { v.toString(w); });
        orderBy.match!((None v) {}, (OrderBy v) { v.toString(w); });
        limit.match!((None v) {}, (Limit v) { v.toString(w); });
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
    mixin(makeCtor!(typeof(value))("value"));
    mixin(makeAssign!(typeof(this))(["value"]));
}

struct ResultColumnExpr {
    SumType!(Blob, Query*) value;
    mixin ToStringSumType!value;
    mixin(makeCtor!(typeof(value))("value"));
    mixin(makeAssign!(typeof(this))(["value"]));
}

struct From {
    SumType!(TableOrSubQueries, Blob) value;
    alias value this;
    mixin(makeCtor!(typeof(value))("value"));
    mixin(makeAssign!(typeof(this))(["value"]));

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
    mixin(makeAssign!(typeof(this))(["value"]));

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
    mixin(makeAssign!(typeof(this))(["required", "optional"]));

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
    mixin(makeAssign!(typeof(this))(["value"]));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        value.match!((TableOrSubQuerySelect* v) { v.toString(w); }, (TableOrSubQueries* v) {
            put(w, "(");
            v.toString(w);
            put(w, ")");
        }, (TableRef v) { v.toString(w); }, (Blob v) { v.toString(w); });
    }
}

struct TableOrSubQuerySelect {
    Select select;
    TableAlias alias_;
    mixin(makeAssign!(typeof(this))(["select", "alias_"]));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, "(");
        select.toString(w);
        put(w, ")");
        alias_.toString(w);
    }
}

struct OrderBy {
    OrderingTerm required;
    OrderingTerm[] optional;
    mixin(makeAssign!(typeof(this))(["required", "optional"]));

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
    mixin(makeAssign!(typeof(this))(["expr", "sortTerm"]));

    this(Blob expr, OrderingTermSort sortTerm) @safe pure nothrow @nogc {
        this.expr = expr;
        this.sortTerm = sortTerm;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        expr.match!((None n) {}, (Blob v) { v.toString(w); });
        sortTerm.match!((None n) {}, (OrderingTermSort v) {
            put(w, " ");
            put(w, v.to!string);
        });
    }
}

enum OrderingTermSort {
    ASC,
    DESC,
}

struct Limit {
    SumType!(None, Blob) expr;
    SumType!(None, LimitOffset, Blob) optional;
    mixin(makeCtor!(typeof(expr))("expr"));
    mixin(makeAssign!(typeof(this))(["expr", "optional"]));

    this(Blob expr, LimitOffset l) @safe pure nothrow @nogc {
        this.expr = expr;
        this.optional = l;
    }

    this(Blob expr, Blob l) @safe pure nothrow @nogc {
        this.expr = expr;
        this.optional = l;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, " LIMIT ");
        expr.match!((None n) {}, (Blob v) { v.toString(w); });
        optional.match!((None n) {}, (LimitOffset v) {
            put(w, " OFFSET ");
            v.toString(w);
        }, (Blob v) { put(w, ","); v.toString(w); });
    }
}

struct LimitOffset {
    Blob expr;
    alias expr this;
}

// #########################################################################
/// # Select END
// #########################################################################

// #########################################################################
/// # Insert START
// #########################################################################

struct Insert {
    /// Type of operation to perform.
    InsertOpt opt;
    /// Table to operate on.
    TableRef table;
    TableAlias alias_;
    ///
    InsertColumns columns;
    ///
    InsertValues values;

    ///
    this(InsertOpt opt, TableRef tbl) @safe pure nothrow @nogc {
        this.opt = opt;
        this.table = tbl;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        final switch (opt) with (InsertOpt) {
        case Insert:
            put(w, "INSERT");
            break;
        case Replace:
            put(w, "REPLACE");
            break;
        case InsertOrReplace:
            put(w, "INSERT OR REPLACE");
            break;
        case InsertOrRollback:
            put(w, "INSERT OR ROLLBACK");
            break;
        case InsertOrAbort:
            put(w, "INSERT OR ABORT");
            break;
        case InsertOrFail:
            put(w, "INSERT OR FAIL");
            break;
        case InsertOrIgnore:
            put(w, "INSERT OR IGNORE");
            break;
        }
        put(w, " INTO ");
        table.toString(w);
        alias_.toString(w);
        columns.toString(w);
        values.toString(w);
    }
}

struct InsertColumns {
    SumType!(None, ColumnNames) value;
    mixin(makeCtor!(typeof(value))("value"));
    mixin(makeAssign!(typeof(this))(["value"]));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        value.match!((None v) {}, (ColumnNames v) => v.toString(w));
    }
}

struct ColumnNames {
    ColumnName required;
    ColumnName[] optional;

    this(ColumnName r, ColumnName[] o = null) {
        required = r;
        optional = o;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, " ('");
        required.toString(w);
        foreach (v; optional) {
            put(w, "','");
            v.toString(w);
        }
        put(w, "')");
    }
}

alias ColumnName = Blob;

struct InsertValues {
    SumType!(None, Select, Values, InsertDefaultValue) value;
    mixin(makeCtor!(typeof(value))("value"));

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        value.match!((None v) {}, (Select v) { put(w, " "); v.toString(w); }, (Values v) {
            v.toString(w);
        }, (InsertDefaultValue v) { put(w, " "); v.toString(w); });
    }
}

struct Values {
    Value required;
    Value[] optional;

    this(Value r, Value[] o = null) {
        required = r;
        optional = o;
    }

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, " VALUES (");
        required.toString(w);
        put(w, ")");
        foreach (v; optional) {
            put(w, ",(");
            v.toString(w);
            put(w, ")");
        }
    }
}

struct Value {
    Expr required;
    Expr[] optional;

    this(Expr r, Expr[] o = null) {
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

alias InsertDefaultValue = Constant!"DEFAULT VALUES";

/// Based on those that are valid in SQLite.
enum InsertOpt {
    Insert,
    Replace,
    InsertOrReplace,
    InsertOrRollback,
    InsertOrAbort,
    InsertOrFail,
    InsertOrIgnore,
}

// #########################################################################
/// # Insert END
// #########################################################################

// #########################################################################
/// # Delete START
// #########################################################################

struct Delete {
    TableRef table;
    SumType!(None, Where) where;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, "DELETE FROM ");
        table.toString(w);
        where.match!((None v) {}, (Where v) { v.toString(w); });
    }
}

// #########################################################################
/// # Delete END
// #########################################################################

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

/// A node representing a constant value.
struct Constant(string s) {
    string value = s;
    alias value this;

    void toString(Writer)(ref Writer w) if (isOutputRange!(Writer, char)) {
        put(w, value);
    }
}

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

/// an opAssign that assign to `var` of type `SumT`.
string makeAssign(T)(string[] members) {
    string rval = format(`void opAssign(%1$s rhs) @trusted pure nothrow @nogc {`, T.stringof);
    foreach (m; members) {
        rval ~= format("%1$s = rhs.%1$s;", m);
    }
    rval ~= "}\n";
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

version (unittest) {
    import unit_threaded.assertions : shouldEqual;
}

// TODO: investigate why this is needed to be system.
@system:

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
    qblob.from = Blob("foo").From;
    qtblRef.from = TableOrSubQueries(TableOrQuery(TableRef("foo"))).From;
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
    qsubBlob.from = Blob("foo I dance").From;
    qblob.from = TableOrSubQueries(TableOrQuery(new TableOrSubQuerySelect(qsubBlob))).From;
    qAlias.from = TableOrSubQueries(TableOrQuery(new TableOrSubQuerySelect(qsubBlob,
            TableAlias("bar")))).From;
    qRef.from = TableOrSubQueries(TableOrQuery(new TableOrSubQueries(TableRef("foo")
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
    q.from = Blob("foo").From;
    // act
    q.orderBy = OrderBy(OrderingTerm(Blob("bar")));
    // assert
    q.Query.Sql.toString.shouldEqual("SELECT * FROM foo ORDER BY bar;");
}

@("shall convert a Select using Where to SQL")
unittest {
    // arrange
    Select q;
    // act
    q.from = Blob("foo").From;
    q.where = WhereExpr(Expr("foo = bar"), [
            WhereExpr.Opt(WhereOp.OR, Expr("batman NOT NULL"))
            ]).Where;
    // assert
    q.Query.Sql.toString.shouldEqual("SELECT * FROM foo WHERE foo = bar OR batman NOT NULL;");
}

@("shall convert an Insert using default values to SQL")
unittest {
    // act
    auto q = Insert(InsertOpt.Insert, TableRef("foo"));
    q.values = InsertValues(InsertDefaultValue.init);
    // assert
    q.Query.Sql.toString.shouldEqual("INSERT INTO foo DEFAULT VALUES;");
}

@("shall convert an Insert using specific values to SQL")
unittest {
    // act
    auto q = Insert(InsertOpt.Insert, TableRef("foo"));
    q.values = InsertValues(Values(Value(Expr("1"), [Expr("2")]), [
                Value(Expr("4"), [Expr("5")])
            ]));
    // assert
    q.Query.Sql.toString.shouldEqual("INSERT INTO foo VALUES (1,2),(4,5);");
}

@("shall convert an Insert using select stmt to SQL")
unittest {
    // act
    Select s;
    s.from = Blob("bar").From;
    auto q = Insert(InsertOpt.Insert, TableRef("foo"));
    q.values = InsertValues(s);
    // assert
    q.Query.Sql.toString.shouldEqual("INSERT INTO foo SELECT * FROM bar;");
}

@("shall convert a Select with a limit to SQL")
unittest {
    // arrange
    Select q;
    q.from = Blob("foo").From;
    // act
    q.limit = Limit(Blob("10"), LimitOffset(Blob("42")));
    // assert
    q.Query.Sql.toString.shouldEqual("SELECT * FROM foo LIMIT 10 OFFSET 42;");
}
