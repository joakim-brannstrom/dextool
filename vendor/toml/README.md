Implementation of [Tom's Obvious, Minimal Language](https://github.com/toml-lang/toml/blob/master/README.md) for D, based on
[TOML 0.4.0](https://github.com/toml-lang/toml/blob/master/versions/en/toml-v0.4.0.md)

[![Build Status](https://travis-ci.org/Kripth/toml.svg?branch=master)](https://travis-ci.org/Kripth/toml) 
[![Code Coverage](https://codecov.io/gh/Kripth/toml/branch/master/graph/badge.svg)](https://codecov.io/gh/Kripth/toml)
[![DUB Package](https://img.shields.io/dub/v/toml.svg)](https://code.dlang.org/packages/toml)
[![DUB Downloads](https://img.shields.io/dub/dt/toml.svg)](https://code.dlang.org/packages/toml) 

# Usage

```d
import toml;

TOMLDocument doc;

doc = parseTOML("example = 1");
assert(doc["example"].integer == 1);

doc = parseTOML(`
	bool = true
	integer = 42
	floating = 1e2
	string = "string"
`)
assert(doc["bool"] == true);
assert(doc["integer"] == 42);
assert(doc["floating"] == 1e2);
assert(doc["string"] == "string");

// from a file
import std.file : read;
doc = parseTOML(cast(string)read("/path/to/file.toml"));
```

# Conversion

- [toml:json](json)
