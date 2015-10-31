void fun();

class Smurf {
public:
    Smurf();
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
