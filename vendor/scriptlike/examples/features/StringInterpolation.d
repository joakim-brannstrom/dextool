import scriptlike;

void main()
{
	// Output: The number 21 doubled is 42!
	int num = 21;
	writeln( mixin(interp!"The number ${num} doubled is ${num * 2}!") );

	// Output: Empty braces output nothing.
	writeln( mixin(interp!"Empty ${}braces ${}output nothing.") );

	// Output: Multiple params: John Doe.
	auto first = "John", last = "Doe";
	writeln( mixin(interp!`Multiple params: ${first, " ", last}.`) );
}
