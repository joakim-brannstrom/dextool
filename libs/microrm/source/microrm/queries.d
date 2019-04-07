module microrm.queries;

import std.algorithm : joiner, map;
import std.exception : enforce;
import std.string : join;

import d2sqlite3;
import sumtype;

import microrm.api : Microrm;
import microrm.exception;
import microrm.schema : tableName, fieldToCol, fieldToCol, ColumnName;

public import microrm.query_ast : OrderingTermSort, InsertOpt;

debug (microrm) import std.stdio : stderr;

version (unittest) {
    import unit_threaded.assertions;
}

auto select(T)() {
    return Select!T(tableName!T);
}

struct Select(T) {
    import std.traits : isNumeric, isSomeString;
    import microrm.query_ast;

    microrm.query_ast.Select query;

    this(microrm.query_ast.Select q) {
        this.query = q;
    }

    this(string from) {
        this.query.opts.from = Blob(from).From;
    }

    /// Convert to a SQL statement that can e.g. be pretty printed.
    Sql toSql() {
        return query.Query.Sql;
    }

    /// Count the number of matching rows.
    auto count() @safe pure {
        microrm.query_ast.Select rval = query;
        rval.columns.required = ResultColumn(ResultColumnExpr(Blob("count(*)")));
        return Select!T(rval);
    }

    /// Order the result by `s` in the order the fields are defined in `T`.
    auto orderBy(OrderingTermSort s) @safe pure {
        enum fields = fieldToCol!("", T);

        OrderingTerm[] optional;
        static foreach (i, field; fields) {
            static if (i == 0)
                auto required = OrderingTerm(Blob(field.columnName), s);
            else
                optional ~= OrderingTerm(Blob(field.columnName), s);
        }

        microrm.query_ast.Select rval = query;
        rval.opts.orderBy = OrderBy(required, optional);
        return Select!T(rval);
    }

    auto where(T)(string lhs, T rhs) if (isNumeric!T || isSomeString!T) {
        import std.format : format;

        return this.where(format("%s %s", lhs, rhs));
    }

    /// Add a WHERE condition.
    auto where(string condition) @safe pure {
        static struct WhereOptional {
            Select!T value;
            alias value this;

            private auto where(string condition, WhereOp op) @safe pure {
                import sumtype;

                Select!T rval = value;

                Where w = value.query.opts.where.tryMatch!((Where v) => v);
                WhereExpr we = w.tryMatch!((WhereExpr v) => v);
                we.optional ~= WhereExpr.Opt(op, Expr(condition));
                rval.query.opts.where = Where(we);
                return WhereOptional(rval);
            }

            WhereOptional and(string condition) @safe pure {
                return where(condition, WhereOp.AND);
            }

            WhereOptional or(string condition) @safe pure {
                return where(condition, WhereOp.OR);
            }
        }

        microrm.query_ast.Select rval = query;
        rval.opts.where = WhereExpr(Expr(condition)).Where;

        return WhereOptional(typeof(this)(rval));
    }
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
    return Insert!T(tableName!T);
}

struct Insert(T) {
    import microrm.query_ast;

    microrm.query_ast.Insert query;

    this(microrm.query_ast.Insert q) {
        this.query = q;
    }

    this(string tableName) {
        this.query.table = TableRef(tableName);
    }

    /// Convert to a SQL statement that can e.g. be pretty printed.
    Sql toSql() {
        return query.Query.Sql;
    }

    void run(ref Microrm db) {
        db.run(toSql.toString);
    }

    auto op(InsertOpt o) @safe pure nothrow const @nogc {
        microrm.query_ast.Insert rval = query;
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

        microrm.query_ast.Insert rval = query;
        rval.values = InsertValues(values);
        return Insert!T(rval);
    }

    /// Insert a new row.
    auto insert() @safe pure nothrow const {
        return op(InsertOpt.Insert).setColumns(true);
    }

    /// Replace an existing row.
    auto replace() @safe pure nothrow const {
        return op(InsertOpt.InsertOrReplace).setColumns(false);
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
                columns.required = microrm.query_ast.ColumnName(field.columnName);
                addRequired = false;
            } else
                columns.optional ~= microrm.query_ast.ColumnName(field.columnName);
        }

        microrm.query_ast.Insert rval = query;
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

    insert!Foo.replace.values(1).toSql.toString.shouldEqual(
            "INSERT OR REPLACE INTO Foo ('id','text','val','ts','version') VALUES (?,?,?,?,?);");
    insert!Foo.insert.values(1).toSql.toString.shouldEqual(
            "INSERT INTO Foo ('text','val','ts','version') VALUES (?,?,?,?);");

    insert!Foo.replace.values(2).toSql.toString.shouldEqual(
            "INSERT OR REPLACE INTO Foo ('id','text','val','ts','version') VALUES (?,?,?,?,?),(?,?,?,?,?);");

    insert!Foo.insert.values(2).toSql.toString.shouldEqual(
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

    insert!Bar.replace.values(1).toSql.toString.shouldEqual(
            "INSERT OR REPLACE INTO Bar ('id','value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?,?);");
    insert!Bar.insert.values(1).toSql.toString.shouldEqual(
            "INSERT INTO Bar ('value','foo.id','foo.text','foo.val','foo.ts') VALUES (?,?,?,?,?);");
    insert!Bar.insert.values(3).toSql.toString.shouldEqual(
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

    insert!Baz.replace.values(1).toSql.toString.shouldEqual("INSERT OR REPLACE INTO Baz ('id','v','xyz.v','xyz.foo.text','xyz.foo.val','xyz.foo.ts','w') VALUES (?,?,?,?,?,?,?);");
}

auto delete_(T)() {
    return Delete!T(tableName!T);
}

struct Delete(T) {
    import microrm.query_ast;

    microrm.query_ast.Delete query;

    this(microrm.query_ast.Delete q) {
        this.query = q;
    }

    this(string tableName) {
        this.query.table = TableRef(tableName);
    }

    /// Convert to a SQL statement that can e.g. be pretty printed.
    Sql toSql() {
        return query.Query.Sql;
    }

    void run(ref Microrm db) {
        db.run(toSql.toString);
    }

    /// Add or replace a WHERE condition.
    auto where(string condition) @safe pure {
        static struct WhereOptional {
            Delete!T value;
            alias value this;

            private auto where(string condition, WhereOp op) @safe pure {
                import sumtype;

                Delete!T rval = value;

                // there should always be a Where in the sumtype because that
                // is what is initialized to.
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

        microrm.query_ast.Delete rval = query;
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
    return Count!T(tableName!T);
}

struct Count(T) {
    Select!T query;
    alias query this;

    this(microrm.query_ast.Select q) {
        this.query = Select!T(q);
    }

    this(string from) {
        this.query = Select!T(from).count;
    }

    /// Add a WHERE condition.
    auto where(string condition) @safe pure {
        import microrm.query_ast;

        static struct WhereOptional {
            Count!T value;
            alias value this;

            private auto where(string condition, WhereOp op) @safe pure {
                import sumtype;

                Count!T rval = value;

                Where w = value.query.query.opts.where.tryMatch!((Where v) => v);
                WhereExpr we = w.tryMatch!((WhereExpr v) => v);
                we.optional ~= WhereExpr.Opt(op, Expr(condition));
                rval.query.query.opts.where = Where(we);
                return WhereOptional(rval);
            }

            WhereOptional and(string condition) @safe pure {
                return where(condition, WhereOp.AND);
            }

            WhereOptional or(string condition) @safe pure {
                return where(condition, WhereOp.OR);
            }
        }

        microrm.query_ast.Select rval = query.query;
        rval.opts.where = WhereExpr(Expr(condition)).Where;

        return WhereOptional(typeof(this)(rval));
    }
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
