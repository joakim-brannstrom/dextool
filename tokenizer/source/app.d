module app;
import tested;
import std.stdio;

import app_main : rmain;

@name("Test a test") unittest {
    writeln("app unit test running");
}

shared static this() {
    version (unittest) {
        import core.runtime;

        Runtime.moduleUnitTester = () => true;
        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        assert(runUnitTests!app(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

int main(string[] args) {
    version (unittest) {
        writeln(`This application does nothing. Run with "dub build -bunittest"`);
        return 0;
    }
    else {
        return rmain(args);
    }
}
