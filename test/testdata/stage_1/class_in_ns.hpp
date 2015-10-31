namespace foo {

namespace bar {

/// Description
class Smurf {
public:
    Smurf() = default;
    Smurf(const Smurf& other) = delete;
    virtual ~Smurf() {}

    virtual Smurf& operator=(const Smurf& other) {}

private:

};

} // NS: bar

} // NS: foo
