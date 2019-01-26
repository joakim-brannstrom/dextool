#!/usr/bin/env dub
/+ dub.sdl:
    name "fake_cc"
+/

import std.stdio : writeln;

void main(string[] args) {
    writeln("#include <...> search starts here:");
    writeln("/foo/bar");
    writeln("End of search list.");
}
