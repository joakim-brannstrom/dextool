// bug when wchar_t is used, it crashed.
// This bug only show up when running cpptestdouble with file ending .hpp
//
// expecting to proceed as usual.

#include <wchar.h>

namespace N {

wchar_t* fun();

} // NS: N
