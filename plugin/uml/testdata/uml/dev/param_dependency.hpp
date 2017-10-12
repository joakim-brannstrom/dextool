class A {
};

class A_OneParam {
    void one_param(A a);
};

class A_ByReturn {
    A retval();
};

class A_ByPtrReturn {
    A* retval();
};

class A_ByCtor {
    A_ByCtor(A a);
};

class B {
};

class AB_ParamReturn {
    A param(B);
};

class Forward;

// Not a problem, same as A_ByPtrReturn
class Forward_ByPtr {
    Forward* retval();
};

namespace ns1 {
class Forward;
} // NS: ns1

// Problematic when nested in ns
class Forward_ByNsPtr {
    ns1::Forward* retval();
};
