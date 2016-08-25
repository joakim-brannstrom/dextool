typedef char* some_pointer;
typedef double MadeUp;

class Methods {
public:
    Methods();
    Methods(char foo);
    ~Methods();

    void func1();
    int func2();
    char* func6(some_pointer w);
    float func7(int& y, char* yy);
    const double func3(int x, const int xx);
    const void* const func4(MadeUp z, const MadeUp zz, const MadeUp& zzz, const MadeUp** const zzzz);
    void operator=(const Methods& other);
};

class Virtual {
public:
    Virtual();
    Virtual(char foo);
    virtual ~Virtual();

    // virtual
    virtual void func1();
    virtual int func2();
    virtual char* func6(some_pointer w);
    virtual float func7(int& y, char* yy);
    virtual const double func3(int x, const int xx);
    virtual const void* const func4(MadeUp z, const MadeUp zz, const MadeUp& zzz, const MadeUp** const zzzz);
    virtual void operator=(const Virtual& other);
};

class Abstract {
public:
    Abstract();
    virtual ~Abstract();

    void func1();
    virtual void func2();
    virtual void func3() = 0;
};
