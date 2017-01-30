#ifndef CLASS_METHOD_BODY_HPP
#define CLASS_METHOD_BODY_HPP

void ctor();
void copy_ctor();
void dtor();
void method();

class InlineMethods {
public:
    InlineMethods() {
        ctor();
    }
    InlineMethods(const InlineMethods&) {
        copy_ctor();
    }
    ~InlineMethods() {
        dtor();
    }

    void func() {
        method();
    }
};

class Methods {
public:
    Methods();
    Methods(const Methods&);
    ~Methods();

    void call_free_func();
    void local_func();
    void call_local_func();
};

Methods::Methods() {
    ctor();
}
Methods::Methods(const Methods&) {
    copy_ctor();
}
Methods::~Methods() {
    dtor();
}
void Methods::call_free_func() {
    method();
}
void Methods::local_func() {
    method();
}
void Methods::call_local_func() {
    local_func();
}

class Dummy {
public:
    void fun() {}
};

class CallOtherClass {
public:
    void func() {
        a.fun();
    }

    Dummy a;
};

struct Indirect {
    typedef int myInt;
    myInt a;
    bool b;
    Dummy c;
};

class IndirectDependencyViaUsage {
public:
    void func() {
        indirect.a;
        indirect.b;
        indirect.c.fun();
    }

    Indirect indirect;
};

class CallSelf {
public:
    bool self(const char* pattern, const char* str) {
        // the recursive calls causes an infinite loop
        switch (*pattern) {
        case '\0':
            return true;
        case '*':
            return (*str != '\0') && self(pattern, str + 1);
        default:
            return (*pattern == *str) && self(pattern + 1, str + 1);
        }
    }
};

// Test the generated relations from method bodies to those nodes it uses.
class MethodVariables {
public:
    typedef int myInt;

    int simple(int ix) {
        int r = 3;
        return r;
    }

    // expecting a relation from use_typedef to myInt
    int use_typedef(int ix) {
        myInt r = 3;
        return r;
    }

    int* ptr(int ix) {
        int* r = new int;
        return r;
    }

    int*& ptr_ref(int ix) {
        int* r0 = new int;
        int*& r1 = r0;
        return r1;
    }

    int*& ptr_ref_typedef(int ix) {
        myInt* r0 = new int;
        myInt*& r1 = r0;
        return r1;
    }

    // builtins used inside a function do not result in a node
    void my_builtin() {
        __builtin_huge_valf();
    }

    union {
        char union_buf[10];
        int size;
    };

    void use_field_from_union() {
        char c = union_buf[0];
    }
};

// Test nesting representation of classes
class Top {
};

class NestA {
public:
    class NestB {
        NestB(Top& x);

        class NestC {
        };
    };
};

template<typename T>
class TopTemplate {
};

// Test the same but for templates
template<typename T>
class TemplateA {
public:
    typedef T ParamType;

    class TemplateInner {
    public:
        TemplateInner(const TopTemplate<ParamType> x);
    };
};

#endif // CLASS_METHOD_BODY_HPP
