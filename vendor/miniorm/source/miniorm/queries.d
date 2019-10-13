module miniorm.queries;

import std.algorithm : joiner, map;
import std.exception : enforce;
import std.string : join;

import d2sqlite3;
import sumtype;

import miniorm.api : Miniorm;
import miniorm.exception;
import miniorm.schema : tableName, fieldToCol, fieldToCol, ColumnName;

public import miniorm.query_ast : OrderingTermSort, InsertOpt;

debug (miniorm) import std.stdio : stderr;

version (unittest) {
    import unit_threaded.assertions;
}

auto select(T)() {
    return Select!T(tableName!T);
}

struct Select(T) {
    import miniorm.query_ast;

    miniorm.query_ast.Select query;

    this(miniorm.query_ast.Select q) {
        this.query = q;
    }

    this(string from) {
        this.query.from = Blob(from).From;
    }

    /// Convert to a SQL statement that can e.g. be pretty printed.
    Sql toSql() {
        return query.Query.Sql;
    }

    /// Count the number of matching rows.
    auto count() @safe pure {
        miniorm.query_ast.Select rval = query;
        rval.columns.required = ResultColumn(ResultColumnExpr(Blob("count(*)")));
        return Select!T(rval);
    }

    /// Order the result by `s` in the order the fields are defined in `T`.
    auto orderBy(OrderingTermSort s, string[] fields = null) @trusted pure {
        OrderingTerm required;
        OrderingTerm[] optional;

        if (fields) {
            required = OrderingTerm(Blob("'" ~ fields[0] ~ "'"), s);
            foreach (f; fields[1 .. $])
                optional ~= OrderingTerm(Blob("'" ~ f ~ "'"), s);
        } else {
            enum fields_ = fieldToCol!("", T);
            static foreach (i, field; fields_) {
                static if (i == 0)
                    required = OrderingTerm(Blob(field.quoteColumnName), s);
                else
                    optional ~= OrderingTerm(Blob(field.quoteColumnName), s);
            }
        }

        miniorm.query_ast.Select rval = query;
        rval.orderBy = OrderBy(required, optional);
        return Select!T(rval);
    }

    /// Limit the query to this number of answers
    auto limit(long value) @trusted pure {
        import std.conv : to;

        miniorm.query_ast.Select rval = query;
        rval.limit = Limit(Blob(value.to!string));
        return Select!T(rval);
    }

    mixin WhereMixin!(T, typeof(this), miniorm.query_ast.Select);
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        ulong ts;
    }

    select!Foo.where("foo = bar").or("batman IS NULL").and("batman = hero")
        .toSql.toString.shouldEqual(
                "SELECT * FROM Foo WHERE foo = bar OR batman IS NULL AND batman = hero;");
}

@("shall be possible to have a member of enum type")
unittest {
    static struct Foo {
        enum MyEnum : string {
            foo = "batman",
            bar = "robin",
        }

        ulong id;
        MyEnum enum_;
    }

    select!Foo.where("enum_ = 'robin'")
        .toSql.toString.shouldEqual("SELECT * FROM Foo WHERE enum_ = 'robin';");
}

auto insert(T)() {
    return Insert!T(tableName!T).insert;
}

auto insertOrReplace(T)() {
    return Insert!T(tableName!T).insertOrReplace;
}

auto insertOrIgnore(T)() {
    return Insert!T(tableName!T).insertOrIgnore;
}

struct Insert(T) {
    import miniorm.query_ast;

    miniorm.query_ast.Insert query;

    this(miniorm.query_ast.Insert q) {
        this.query = q;
    }

    this(string tableName) {
        this.query.table = TableRef(tableName);
    }

    /// Convert to a SQL statement that can e.g. be pretty printed.
    Sql toSql() {
        return query.Query.Sql;
    }

    void run(ref Miniorm db) {
        db.run(toSql.toString);
    }

    auto op(InsertOpt o) @safe pure nothrow const @nogc {
        miniorm.query_ast.Insert rval = query;
        rval.opt = o;
        return Insert!T(rval);
    }

    /// Returns: number of values that the query is sized for.
    size_t getValues() {
        return query.values.value.match!((Values v) => 1 + v.optional.length, _ => 0);
    }

    /// Returns: number of columns to insert per value.
    size_t getColumns() {
        return query.columns.value.match!((ColumnNames v) => 1 + v.optional.length, (None v) => 0);
    }

    /// Number of values the user wants to insert.
    auto values(size_t cnt)
    in(cnt >= 1, "values must be >=1") {
        import std.array : array;
        import std.range : repeat;

        Value val;
        val.required = Expr("?");
        val.optional = query.columns.value.match!((ColumnNames v) => Expr("?")
                .repeat(v.optional.length).array, (None v) => null);

        Values values;
        foreach (i; 0 .. cnt) {
            if (i == 0)
                values.required = val;
            else
                values.optional ~= val;
        }

        miniorm.query_ast.Insert rval = query;
        rval.values = InsertValues(values);
        return Insert!T(rval);
    }

    /// Insert a new row.
    auto insert() @safe pure nothrow const {
        return op(InsertOpt.Insert).setColumns(true);
    }

    /// Insert or replace an existing row.
    auto insertOrReplace() @safe pure nothrow const {
        return op(InsertOpt.InsertOrReplace).setColumns(false);
    }

    auto insertOrIgnore() @safe pure nothrow const {
        return op(InsertOpt.InsertOrIgnore).setColumns(false);
    }

    // TODO the name is bad.
    /// Specify columns to insert/replace values in.
    private auto setColumns(bool insert_) @safe pure const {
        enum fields = fieldToCol!("", T);

        ColumnNames columns;
        bool addRequired = true;
        foreach (field; fields) {
            if (field.isPrimaryKey && insert_)
                continue;

            if (addRequired) {
                columns.required = miniorm.query_ast.ColumnName(field.columnName);
                addRequired = false;
            } else
                columns.optional ~= miniorm.query_ast.ColumnName(field.columnName);
        }

        miniorm.query_ast.Insert rval = query;
        rval.columns = InsertColumns(columns);
        return Insert!T(rval);
    }
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        float val;
        ulong ts;

        @ColumnName("version")
        string version_;
    }

    insertOrReplace!Foo.values(1).toSql.toString.shouldEqual(
            "INSERT OR REPLACE INTO Foo ('id','text','val','ts','version') VALUES (?,?,?,?,?);");
    insert!Foo.values(1).toSql.toString.shouldEqual(
            "INSERT INTO Foo ('text','val','ts','version') VALUES (?,?,?,?);");

    insertOrReplace!Foo.values(2).toSql.toString.shouldEqual(
            "INSERT OR REPLACE INTO Foo ('id','text','val','ts','version') VALUES (?,?,?,?,?),(?,?,?,?,?);");

    insertOrIgnore!Foo.values(2).toSql.toString.shouldEqual(
            "INSERT OR IGNORE INTO Foo ('id','text','val','ts','version') VALUES (?,?,?,?,?),(?,?,?,?,?);");

    insert!Foo.values(2).toSql.toString.shouldEqual(
            "INSERT INTO Foo ('text','val','ts','version') VALUES (?,?,?,?),(?,?,?,?);");
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        float val;
        ulong ts;
    }

    static struct Bar {
        ulong id;
        float value;
        Foo foo;
    }

    insertOrReplace!Bar.values(1).toSql.toString.shouldEqual(
            "INSERT OR REPLACE INTO Bar ('id','value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?,?);");
    insertOrIgnore!Bar.values(1).toSql.toString.shouldEqual(
            "INSERT OR IGNORE INTO Bar ('id','value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?,?);");
    insert!Bar.values(1).toSql.toString.shouldEqual(
            "INSERT INTO Bar ('value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?);");
    insert!Bar.values(3).toSql.toString.shouldEqual(
            "INSERT INTO Bar ('value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?),(?,?,?,?,?),(?,?,?,?,?);");
}

unittest {
    struct Foo {
        string text;
        float val;
        ulong ts;
    }

    struct Bar {
        float v;
        Foo foo;
    }

    struct Baz {
        ulong id;
        float v;
        Bar xyz;
        float w;
    }

    insertOrReplace!Baz.values(1).toSql.toString.shouldEqual("INSERT OR REPLACE INTO Baz ('id','v','xyz.v','xyz.foo.text','xyz.foo.val','xyz.foo.ts','w') VALUES (?,?,?,?,?,?,?);");
}

auto delete_(T)() {
    return Delete!T(tableName!T);
}

struct Delete(T) {
    import miniorm.query_ast;

    miniorm.query_ast.Delete query;

    this(miniorm.query_ast.Delete q) {
        this.query = q;
    }

    this(string tableName) {
        this.query.table = TableRef(tableName);
    }

    /// Convert to a SQL statement that can e.g. be pretty printed.
    Sql toSql() {
        return query.Query.Sql;
    }

    void run(ref Miniorm db) {
        db.run(toSql.toString);
    }

    mixin WhereMixin!(T, typeof(this), miniorm.query_ast.Delete);
}

mixin template WhereMixin(T, QueryT, AstT) {
    import std.datetime : SysTime;
    import std.traits : isNumeric, isSomeString;

    /// Automatically quotes `rhs`.
    auto where(string lhs, string rhs) {
        import std.format : format;

        return this.where(format("%s '%s'", lhs, rhs));
    }

    /// Converts `rhs` to a datetime that sqlite understand.
    auto where(string lhs, SysTime rhs) {
        import std.format : format;
        import miniorm.api : toSqliteDateTime;

        return this.where(format("%s datetime('%s')", lhs, rhs.toUTC.toSqliteDateTime));
    }

    auto where(T)(string lhs, T rhs) if (isNumeric!T || isSomeString!T) {
        import std.format : format;

        return this.where(format("%s %s", lhs, rhs));
    }

    /// Add a WHERE condition.
    auto where(string condition) @trusted pure {
        import miniorm.query_ast;

        static struct WhereOptional {
            QueryT!T value;
            alias value this;

            private auto where(string condition, WhereOp op) @trusted pure {
                import sumtype;

                QueryT!T rval = value;

                Where w = value.query.where.tryMatch!((Where v) => v);
                WhereExpr we = w.tryMatch!((WhereExpr v) => v);
                we.optional ~= WhereExpr.Opt(op, Expr(condition));
                rval.query.where = Where(we);
                return WhereOptional(rval);
            }

            WhereOptional and(string condition) @safe pure {
                return where(condition, WhereOp.AND);
            }

            WhereOptional or(string condition) @safe pure {
                return where(condition, WhereOp.OR);
            }
        }

        AstT rval = query;
        rval.where = WhereExpr(Expr(condition)).Where;

        return WhereOptional(typeof(this)(rval));
    }
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        ulong ts;
    }

    delete_!Foo.where("text = privet").and("ts > 123")
        .toSql.toString.shouldEqual("DELETE FROM Foo WHERE text = privet AND ts > 123;");
}

auto count(T)() {
    //return Count!T(Select!T(tableName!T).count);
    //import miniorm.query_ast;
    //
    //miniorm.query_ast.Select query;
    return Count!T(tableName!T);
}

struct Count(T) {
    import miniorm.query_ast : Sql;

    Select!T query_;

    this(miniorm.query_ast.Select q) {
        this.query_ = Select!T(q);
    }

    this(string from) {
        this.query_ = Select!T(from).count;
    }

    /// Convert to a SQL statement that can e.g. be pretty printed.
    Sql toSql() {
        return query_.toSql;
    }

    private ref miniorm.query_ast.Select query() @safe pure nothrow @nogc {
        return query_.query;
    }

    mixin WhereMixin!(T, typeof(this), miniorm.query_ast.Select);
}

unittest {
    static struct Foo {
        ulong id;
        string text;
        ulong ts;
    }

    count!Foo.where("text = privet").and("ts > 123").toSql.toString.shouldEqual(
            "SELECT count(*) FROM Foo WHERE text = privet AND ts > 123;");
}
