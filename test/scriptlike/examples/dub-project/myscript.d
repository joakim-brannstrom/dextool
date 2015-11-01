import scriptlike;

void main(string[] args) {
	writeln("This script is in directory: ", thisExePath.dirName);

	string name;
	if(args.length > 1)
		name = args[1];
	else
		name = userInput!string("What's your name?");

	writeln("Hello, ", name, "!");
}
