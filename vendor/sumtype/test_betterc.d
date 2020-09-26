import sumtype;

version(D_BetterC) {}
else static assert(false, "Must compile with -betterC to run betterC tests");

version(unittest) {}
else static assert(false, "Must compile with -unittest to run betterC tests");

extern(C) int main()
{
	import core.stdc.stdio: puts;

	static foreach (test; __traits(getUnitTests, sumtype)) {
		test();
	}

	puts("All unit tests have been run successfully.");
	return 0;
}
