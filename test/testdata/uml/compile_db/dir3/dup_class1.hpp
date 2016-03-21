#include "file1.hpp"
class Dup {
    virtual void fun();
    // expect 1 x in UML
    ns1::File1 x;
};
