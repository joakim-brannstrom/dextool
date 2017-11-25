# `D2Sqlite3`

[![Build Status](https://travis-ci.org/biozic/d2sqlite3.svg)](https://travis-ci.org/biozic/d2sqlite3)
[![Dub](https://img.shields.io/dub/v/d2sqlite3.svg)](http://code.dlang.org/packages/d2sqlite3)
[![Downloads](https://img.shields.io/dub/dt/d2sqlite3.svg)](https://code.dlang.org/packages/d2sqlite3)

This is a small wrapper around SQLite for the D programming language.
It wraps the C API in an idiomatic manner and handles built-in D types and
`Nullable!T` automatically.

## Documentation

[Online documentation](http://biozic.github.io/d2sqlite3/d2sqlite3.html)

## `dub` configurations

- **`with-lib`** (the default): assumes that SQLite is already installed and available to the linker. Set the right path for the SQLite library in your project's `dub.json` file using the `lflags` setting:

```json
    "lflags": ["-L/path/to/lib"]
```

- **`without-lib`**: you manage linking SQLite yourself.

- **`all-included`**: on Windows, use a prebuilt SQLite DLL (bundled with this library); on Posix systems, builds SQLite from the source amalgamation (bundled with this library), using the default building configuration with these options defined:
  - SQLITE_ENABLE_COLUMN_METADATA
  - SQLITE_ENABLE_UNLOCK_NOTIFY

Set the right configuration for you project in its `dub.json` file using the `subConfigurations` setting, e.g.:

```json
    "subConfigurations": {
        "d2sqlite3": "all-included"
    }
```

## Library versions

These versions can be used to build the library:

- `SqliteEnableColumnMetadata`: to enable corresponding special methods of `Row`.
- `SqliteEnableUnlockNotify`: to enable SQLite's builtin unlock notification mechanism.
- `SqliteFakeUnlockNotify`: to emulate an unlock notification mechanism.

## C binding generation

The D binding file `sqlite3.d` is generated from the C header file `sqlite3.h`, using [jacob-carlborg/dstep](https://github.com/jacob-carlborg/dstep). I try to keep it up to date.
