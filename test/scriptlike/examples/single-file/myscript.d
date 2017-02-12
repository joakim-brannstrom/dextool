#!/usr/bin/env dub
/+ dub.sdl:
	name "myscript"
	dependency "scriptlike" version="~>0.9.6"
+/
import scriptlike;

void main(string[] args) {
	string name;
	if(args.length > 1)
		name = args[1];
	else
		name = userInput!string("What's your name?");

	writeln("Hello, ", name, "!");
}
