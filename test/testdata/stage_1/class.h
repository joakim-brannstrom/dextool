class Foo;
struct FooBar;

class Simple {
public:
    Simple();
    ~Simple();

    void func1();
    int func2();

private:
    int x;
};

class Simple2 {
public:
    Simple2();
    ~Simple2();

    void func1() { int foo = 1; foo++; }

private:
    int x;
};

class OuterClass {
public:
    OuterClass();
    ~OuterClass();

    void func1();
    int func2();

private:
    class InnerClass {
    public:
        InnerClass();
        ~InnerClass();
    private:
        class InnerClass2 {
        public:
            InnerClass2();
            ~InnerClass2();
        };
    };
};
