class OpOverload {
public:
    OpOverload();

    // UAR
    OpOverload operator++();
    OpOverload operator++(int);
    OpOverload operator--();
    OpOverload operator--(int);

    // AOR
    int operator+(const OpOverload&);
    int operator-(const OpOverload&);
    int operator*(const OpOverload&);
    int operator/(const OpOverload&);

    // ROR
    bool operator>(const OpOverload&);
    bool operator>=(const OpOverload&);
    bool operator<(const OpOverload&);
    bool operator<=(const OpOverload&);
    bool operator==(const OpOverload&);
    bool operator!=(const OpOverload&);

    // LCR
    bool operator&&(const OpOverload&);
    bool operator||(const OpOverload&);
};

void relation_operators() {
    int a = 1;
    int b = 2;

    bool c = a < b;
    bool d = a <= b;
    bool e = a > b;
    bool f = a >= b;
    bool g = a == b;
    bool h = a != b;

    OpOverload oa, ob;
    oa < ob;
    oa <= ob;
    oa > ob;
    oa >= ob;
    oa == ob;
    oa != ob;
}

void logical_operators() {
    bool a = true;
    bool b = false;

    bool c = a || b;
    bool d = a && b;

    OpOverload oa, ob;
    oa || ob;
    oa&& ob;
}

void arithemtic_operators() {
    int a = 1;
    int b = 2;

    int c = a + b;
    int d = a - b;
    int e = a * b;
    int f = a / b;

    OpOverload oa, ob;
    oa + ob;
    oa - ob;
    oa* ob;
    oa / ob;
}

void unary_arithmetic_operators() {
    int a;

    a++;
    ++a;
    a--;
    --a;

    OpOverload oa;
    oa++;
    ++oa;
    oa--;
    --oa;
}
