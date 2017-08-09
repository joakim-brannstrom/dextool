class A {
public:
    A() {}
    A(const A& other) {}
    A& operator=(const A& other) {}
    virtual ~A() {};

    operator bool() {
        return true;
    }

private:
    void inline_() {}
    void outside();
};

void A::outside() {}
