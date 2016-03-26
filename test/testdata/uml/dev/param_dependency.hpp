class A {
};

class A_OneParam {
    void one_param(A a);
};

class A_ByReturn {
    A retval();
};

class A_ByCtor {
    A_ByCtor(A a);
};

class B {
};

class AB_ParamReturn {
    A param(B);
};
