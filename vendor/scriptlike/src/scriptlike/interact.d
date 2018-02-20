/**
 * Handling of interaction with users via standard input.
 *
 * Provides functions for simple and common interactions with users in
 * the form of question and answer.
 *
 * Copyright: Copyright Jesse Phillips 2010
 * License:   $(LINK2 https://github.com/Abscissa/scriptlike/blob/master/LICENSE.txt, zlib/libpng)
 * Authors:   Jesse Phillips
 *
 * Synopsis:
 *
 * --------
 * import scriptlike.interact;
 *
 * auto age = userInput!int("Please Enter your age");
 * 
 * if(userInput!bool("Do you want to continue?"))
 * {
 *     auto outputFolder = pathLocation("Where you do want to place the output?");
 *     auto color = menu!string("What color would you like to use?", ["Blue", "Green"]);
 * }
 *
 * auto num = require!(int, "a > 0 && a <= 10")("Enter a number from 1 to 10");
 * --------
 */
module scriptlike.interact;

import std.conv;
import std.file;
import std.functional;
import std.range;
import std.stdio;
import std.string;
import std.traits;

/**
 * The $(D userInput) function provides a means to accessing a single
 * value from the user. Each invocation outputs a provided 
 * statement/question and takes an entire line of input. The result is then
 * converted to the requested type; default is a string.
 *
 * --------
 * auto name = userInput("What is your name");
 * //or
 * string name;
 * userInput("What is your name", name);
 * --------
 *
 * Returns: User response as type T.
 *
 * Where type is bool: 
 *
 *          true on "ok", "continue", 
 *          and if the response starts with 'y' or 'Y'.
 *
 *          false on all other input, include no response (will not throw).
 *
 * Throws: $(D NoInputException) if the user does not enter anything.
 * 	     $(D ConvError) when the string could not be converted to the desired type.
 */
T userInput(T = string)(string question = "")
{
	write(question ~ "\n> ");
	stdout.flush;
	auto ans = readln();

	static if(is(T == bool))
	{
		switch(ans.front)
		{
			case 'y', 'Y':
				return true;
			default:
		}
		switch(ans.strip())
		{
			case "continue":
			case "ok":
				return true;
			default:
				return false;
		}
	} else
	{
		if(ans == "\x0a")
			throw new NoInputException("Value required, "~
			                           "cannot continue operation.");
		static if(isSomeChar!T)
		{
			return to!(T)(ans[0]);
		} else
			return to!(T)(ans.strip());
	}
}

///ditto
void userInput(T = string)(string question, ref T result)
{
	result = userInput!T(question);
}

version(unittest_scriptlike_d)
unittest
{
	mixin(selfCom(["10PM", "9PM"]));
	mixin(selfCom());
	auto s = userInput("What time is it?");
	assert(s == "10PM", "Expected 10PM got" ~ s);
	outfile.rewind;
	assert(outfile.readln().strip == "What time is it?");
	
	outfile.rewind;
	userInput("What time?", s);
	assert(s == "9PM", "Expected 9PM got" ~ s);
	outfile.rewind;
	assert(outfile.readln().strip == "What time?");
}

/**
 * Pauses and prompts the user to press Enter (or "Return" on OSX).
 * 
 * This is similar to the Windows command line's PAUSE command.
 *
 * --------
 * pause();
 * pause("Thanks. Please press Enter again...");
 * --------
 */
void pause(string prompt = defaultPausePrompt)
{
	//TODO: This works, but needs a little work. Currently, it echoes all
	//      input until Enter is pressed. Fixing that requires some low-level
	//      os-specific work.
	//
	//      For reference:
	//      http://stackoverflow.com/questions/6856635/hide-password-input-on-terminal
	//      http://linux.die.net/man/3/termios
	
	write(prompt);
	stdout.flush();
	getchar();
}

version(OSX)
	enum defaultPausePrompt = "Press Return to continue..."; ///
else
	enum defaultPausePrompt = "Press Enter to continue..."; ///


/**
 * Gets a valid path folder from the user. The string will not contain
 * quotes, if you are using in a system call and the path contain spaces
 * wrapping in quotes may be required.
 *
 * --------
 * auto confFile = pathLocation("Where is the configuration file?");
 * --------
 *
 * Throws: NoInputException if the user does not provide a path.
 */
string pathLocation(string action)
{
	import std.algorithm;
	import std.utf : toUTF8;
	import std.string : strip;
	string ans;

	do
	{
		if(ans !is null)
			writeln("Could not locate that file.");
		ans = userInput(action);
		// Quotations will generally cause problems when
		// using the path with std.file and Windows. This removes the quotes.
		ans = ans.filter!(a => !a.among('"', ';')).toUTF8.strip();
		ans = ans[0] == '"' ? ans[1..$] : ans; // removechars skips first char
	} while(!exists(ans));

	return ans;
}

/**
 * Creates a menu from a Range of strings.
 * 
 * It will require that a number is selected within the number of options.
 * 
 * If the the return type is a string, the string in the options parameter will
 * be returned.
 *
 * Throws: NoInputException if the user wants to quit.
 */
T menu(T = ElementType!(Range), Range) (string question, Range options)
					 if((is(T==ElementType!(Range)) || is(T==int)) &&
					   isForwardRange!(Range))
{
	string ans;
	int maxI;
	int i;

	while(true)
	{
		writeln(question);
		i = 0;
		foreach(str; options)
		{
			writefln("%8s. %s", i+1, str);
			i++;
		}
		maxI = i+1;

		writefln("%8s. %s", "No Input", "Quit");
		ans = userInput!(string)("").strip();
		int ians;

		try
		{
			ians = to!(int)(ans);
		} catch(ConvException ce)
		{
			bool found;
			i = 0;
			foreach(o; options)
			{
				if(ans.toLower() == to!string(o).toLower())
				{
					found = true;
					ians = i+1;
					break;
				}
				i++;
			}
			if(!found)
				throw ce;

		}

		if(ians > 0 && ians <= maxI)
			static if(is(T==ElementType!(Range)))
				static if(isRandomAccessRange!(Range))
					return options[ians-1];
				else
				{
					take!(ians-1)(options);
					return options.front;
				}
			else
				return ians;
		else
			writeln("You did not select a valid entry.");
	}
}

version(unittest_scriptlike_d)
unittest
{
	mixin(selfCom(["1","Green", "green","2"]));
	mixin(selfCom());
	auto color = menu!string("What color?", ["Blue", "Green"]);
	assert(color == "Blue", "Expected Blue got " ~ color);

	auto ic = menu!int("What color?", ["Blue", "Green"]);
	assert(ic == 2, "Expected 2 got " ~ ic.to!string);

	color = menu!string("What color?", ["Blue", "Green"]);
	assert(color == "Green", "Expected Green got " ~ color);

	color = menu!string("What color?", ["Blue", "Green"]);
	assert(color == "Green", "Expected Green got " ~ color);
	outfile.rewind;
	assert(outfile.readln().strip == "What color?");
}


/**
 * Requires that a value be provided and valid based on
 * the delegate passed in. It must also check against null input.
 *
 * --------
 * auto num = require!(int, "a > 0 && a <= 10")("Enter a number from 1 to 10");
 * --------
 *
 * Throws: NoInputException if the user does not provide any value.
 *         ConvError if the user does not provide any value.
 */
T require(T, alias cond)(in string question, in string failure = null)
{
	alias unaryFun!(cond) call;
	T ans;
	while(1)
	{
		ans = userInput!T(question);
		if(call(ans))
			break;
		if(failure)
			writeln(failure);
	}

	return ans;
}

version(unittest_scriptlike_d)
unittest
{
	mixin(selfCom(["1","11","3"]));
	mixin(selfCom());
	auto num = require!(int, "a > 0 && a <= 10")("Enter a number from 1 to 10");
	assert(num == 1, "Expected 1 got" ~ num.to!string);
	num = require!(int, "a > 0 && a <= 10")("Enter a number from 1 to 10");
	assert(num == 3, "Expected 1 got" ~ num.to!string);
	outfile.rewind;
	assert(outfile.readln().strip == "Enter a number from 1 to 10");
}


/**
 * Used when input was not provided.
 */
class NoInputException: Exception
{
	this(string msg)
	{
		super(msg);
	}
}

version(unittest_scriptlike_d)
private string selfCom()
{
	string ans = q{
		auto outfile = File.tmpfile();
		auto origstdout = stdout;
		scope(exit) stdout = origstdout;
		stdout = outfile;};

	return ans;
}

version(unittest_scriptlike_d)
private string selfCom(string[] input)
{
	string ans = q{
		auto infile = File.tmpfile();
		auto origstdin = stdin;
		scope(exit) stdin = origstdin;
		stdin = infile;};

	foreach(i; input)
		ans ~= "infile.writeln(`"~i~"`);";
	ans ~= "infile.rewind;";

	return ans;
}
