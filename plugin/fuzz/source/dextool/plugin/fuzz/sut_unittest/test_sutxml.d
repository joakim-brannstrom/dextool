/*import sutxml;
import std.array;

//Test if we get expected namespaces
unittest
{
    assert(SutEnvironment("./namespaces").getAllNamespaces.array
	   == ["foo::bar", "foo::wun::wug"]);
}

//Test if we get expected xml interfaces
unittest
{
    assert(SutEnvironment("./namespaces").getAllXMLInterfaces.array
	   ==  ["./namespaces/foo/bar.xml",
		"./namespaces/foo/namespace.xml",
		"./namespaces/foo/types.xml",
		"./namespaces/foo/wun/wug.xml",
		"./namespaces/global/namespace.xml",
		"./namespaces/global/types.xml"]);
}
*/