typedef char* MadeUp;

class Simple {
public:
    Simple() {}
    Simple(char foo) {}
    ~Simple() {}

    void func1() {}
    int func2() {}
    int func3(int x) {}
    int func3(int x, char* y) {}
    int func4(MadeUp z) {}

private:
    int x;
};
