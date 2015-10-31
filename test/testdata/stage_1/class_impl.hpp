// A class that have:
// - implementation in the header.
// - variables.
// Expecting to skip the implementation and variables.

class Simple {
public:
    Simple() {}
    Simple(char x) { this->x = 0; }
    Simple(int y) : x(y) { x = y; }
    ~Simple() { this->x = 0; }

    void func1() { int foo = 1; foo++; }
    int func2();

private:
    int x;
};

int Simple::func2() {
    int y = 3;
    return y;
}
