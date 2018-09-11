Conversion from TOML to JSON and from JSON to TOML.

[![DUB Package](https://img.shields.io/dub/v/toml.svg)](https://code.dlang.org/packages/toml%3Ajson)

# Usage

```d
import std.json;

import toml;
import toml.json;

auto json = JSONValue([1, 2, 3]);
assert(toTOML(json).type == TOML_TYPE.ARRAY);
assert(toTOML(json) == [1, 2, 3]);

auto toml = parseTOML(`key = "value"`);
assert(toJSON(toml).type == JSON_TYPE.OBJECT);
assert(toJSON(toml) == JSONValue(["key": "value"]));
```
