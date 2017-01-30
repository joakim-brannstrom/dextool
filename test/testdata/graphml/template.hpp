// Test funny, problematic template constructs

#ifndef TEMPLATE_HPP
#define TEMPLATE_HPP

#include <bits/stringfwd.h>
#include <bits/char_traits.h>
#include <libio.h>

// expecting nodes for:
// c:@N@std@S@char_traits>#C
// c:@N@std@S@char_traits>#C@F@assign#&C#&1C#S

// c:@S@_IO_FILE
// when analyzing C the following is classified as a definition:
//  struct Foo;
// it shouldn't be....

#endif // TEMPLATE_HPP
