#ifndef CLASS_PARTIAL_INTERFACE_HPP
#define CLASS_PARTIAL_INTERFACE_HPP

namespace no_inherit {

class JustACtorSoVirtual {
public:
    JustACtorSoVirtual();
};

class NotVirtualWithDtor {
public:
    NotVirtualWithDtor();
    ~NotVirtualWithDtor();
};

class VirtualWithDtor {
public:
    VirtualWithDtor();
    virtual ~VirtualWithDtor();
};

class CtorNotAffectingVirtualClassificationAsYes {
public:
    CtorNotAffectingVirtualClassificationAsYes();
    virtual void foo();
};

class CtorNotAffectingVirtualClassificationAsPure {
public:
    CtorNotAffectingVirtualClassificationAsPure();
    virtual void foo() = 0;
};

class CommonPatternForPureInterface1 {
public:
    CommonPatternForPureInterface1() {}
    virtual ~CommonPatternForPureInterface1() {}
    virtual void expect_func_to_be_mocked();

private:
    CommonPatternForPureInterface1(const CommonPatternForPureInterface1&);
    void operator=(const CommonPatternForPureInterface1&);
};

class CommonPatternForPureInterface2 {
public:
    CommonPatternForPureInterface2() {}
    virtual ~CommonPatternForPureInterface2() {}
    virtual void expect_func_to_be_mocked();

private:
    CommonPatternForPureInterface2(const CommonPatternForPureInterface2&);
    CommonPatternForPureInterface2& operator=(const CommonPatternForPureInterface2&);
};

class AllProtPrivMadePublic {
protected:
    virtual void a_protected();
private:
    virtual void a_private();
};

} // NS: no_inherit

namespace inherit {

class Base {
public:
    Base();
    Base(const Base& other);
    Base& operator=(const Base& other);
    ~Base();

    void base_func();
};

class DerivedNoVirtual : public Base {
public:
    DerivedNoVirtual();
    DerivedNoVirtual(const DerivedNoVirtual& other);
    DerivedNoVirtual& operator=(const DerivedNoVirtual& other);
    ~DerivedNoVirtual();

    void derived_func();
};

class DerivedVirtual : public Base {
public:
    DerivedVirtual();
    DerivedVirtual(const DerivedVirtual& other);
    DerivedVirtual& operator=(const DerivedVirtual& other);
    ~DerivedVirtual();

    virtual void derived_func();
};

} // NS: inherit

#endif // CLASS_PARTIAL_INTERFACE_HPP
