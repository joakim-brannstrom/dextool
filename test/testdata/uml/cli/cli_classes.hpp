class Method {
public:
    virtual void a_pub();

protected:
    void a_prot();

private:
    void a_priv();
};

class A {
};

class ParamDep {
    void one(A a);
};

class InheritDep : public A {
};

class MemberDep {
    A* a_ptr;
    A& a_ref;
    A  a_value;
};
