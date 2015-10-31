// Nested classes.
// Expecting a correct reconstruction with the correct nesting.

class OuterClass {
public:
    OuterClass() {}
    ~OuterClass() {}

    void func1() {}
    int func2() {}

    class InnerClass {
    public:
        InnerClass() {}
        ~InnerClass() {}
    private:
        class InnerClass2 {
        public:
            InnerClass2() {}
            ~InnerClass2() {}
        };
    };
};
