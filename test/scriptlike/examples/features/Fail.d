/++
Example:
--------
$ test
test: ERROR: Need two args, not 0!
$ test abc 123
test: ERROR: First arg must be 'foobar', not 'abc'!
--------
+/

import scriptlike;

void main(string[] args) {
	helper(args);
}

// Throws a Fail exception on bad args:
void helper(string[] args) {
	// Like std.exception.enforce, but bails with no ugly stack trace,
	// and if uncaught, outputs the program name and "ERROR: "
	failEnforce(args.length == 3, "Need two args, not ", args.length-1, "!");

	if(args[1] != "foobar")
		fail("First arg must be 'foobar', not '", args[1], "'!");
}
