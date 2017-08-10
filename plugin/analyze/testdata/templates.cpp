template<typename A>
void template_func() {
    A a;
    if (a > 3) {
        return;
    } else {
        return;
    }
}

template<typename A>
class Class {
    Class() {}
    ~Class() {}

    void ClassMethod() {}
};

template<>
class Class<int> {
    Class() {}
};

class InnerTemplate {
    template<typename A>
    void InnerTemplateMethod() {}
};
