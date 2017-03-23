import sutxml;

//Test if we get expected namespaces
unittest
{
    assert(SutEnvironment("../").getAllNamespaces
	   == ["xmltest::anotherheyo", "xmltest", "xmltest::heyo::test2"]);
}

//Another case
unittest
{
    assert(SutEnvironment("../xmltest/heyo").getAllNamespaces
	   == ["test2"]);
}

//Test if we get expected xml interfaces
unittest
{
    assert(SutEnvironment("../").getAllXMLInterfaces
	   ==  ["../xmltest/anotherheyo/global.xml", "../xmltest/test.xml", "../xmltest/heyo/test2/test2.xml"]);
}

//Another case
unittest
{
    assert(SutEnvironment("../xmltest/heyo/test2").getAllXMLInterfaces
	   == ["../xmltest/heyo/test2/test2.xml"]);  
}
