// Expecting generation of google mock implementations for all classes.

class Global1 {
public:
    virtual void func1() const = 0;
};

class Global2 {
public:
    virtual void func1() const = 0;
};

// even non-pure classes have a gmock generated for them
class Global3 {
public:
    virtual void func1() {}
};

namespace ns {
class InsideNs1 {
public:
    virtual void func1() const = 0;
};

namespace ns2 {
class InsideNs2 {
public:
    virtual void func1() const = 0;
};
} // NS: ns2
} // NS: ns
