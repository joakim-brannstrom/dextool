import std.stdio;

import docopt;

int main(string[] args) {

    auto doc = "Naval Fate.

    Usage:
    naval_fate ship new <name>...
    naval_fate ship <name> move <x> <y> [--speed=<kn>]
    naval_fate ship shoot <x> <y>
    naval_fate mine (set|remove) <x> <y> [--moored|--drifting]
    naval_fate -h | --help
    naval_fate --version

    Options:
    -h --help     Show this screen.
    --version     Show version.
    --speed=<kn>  Speed in knots [default: 10].
    --moored      Moored (anchored) mine.
    --drifting    Drifting mine.
";

    auto arguments = docopt.docopt(doc, args[1..$], true, "0.3.0");
    writeln(arguments);
    return 0;
}
