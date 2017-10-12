class A;

class B {
    void no_dependency(
        void* x0,
        bool x1,
        unsigned char x2,
        unsigned short x3,
        unsigned int x4,
        unsigned long x5,
        unsigned long long x6,
        char x7,
        // wchar x8,
        short x9,
        int x10,
        long x11,
        long long x12,
        float x13,
        double x14,
        long double x15
    );

    void a_dependency(A* a);
};
