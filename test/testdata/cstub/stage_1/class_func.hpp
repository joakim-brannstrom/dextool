// should ignore C++ code in global namespace

void fun();

class Smurf {
public:
    Smurf();
    Smurf(int);
    ~Smurf() {}
};

namespace foo {
void gun();

namespace bar {

class Smurf {
public:
    Smurf();
    ~Smurf() {}
};

} // NS: bar

} // NS: foo
