// Expecting that the const functions can still manipulate the test data.

class Simple {
public:
    Simple() {}
    virtual ~Simple() {}

    virtual void func1() const = 0;
};
