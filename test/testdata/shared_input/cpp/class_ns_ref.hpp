// Test referencing to types via namespace.

namespace Foo {
class Bar {
public:
    Bar() {}
};
} // NS: Foo

class Glass {
public:
    Glass() {}
    virtual ~Glass() {}

    virtual Foo::Bar func1() = 0;
    virtual Foo::Bar& func2() = 0;
    virtual Foo::Bar* func3() = 0;
    virtual ::Foo::Bar func4() = 0;
    virtual ::Foo::Bar& func5() = 0;
};
