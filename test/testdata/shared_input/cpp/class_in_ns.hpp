namespace foo {

namespace bar {

class Smurf {
public:
    Smurf() = default;
    Smurf(const Smurf& other) = delete;
    virtual ~Smurf() {}

    virtual Smurf& operator=(const Smurf& other) {}
};

} // NS: bar

} // NS: foo
