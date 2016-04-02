class A {
};

class B {
    A a;
};

class C {
    A* a;
};

class D : public A {
};

class CountTest : public A {
    A a0;
    A* a1;
    A& a2;
};
