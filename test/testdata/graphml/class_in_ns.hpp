namespace foo {

namespace bar {

class Smurf {
public:
    Smurf() = default;
    Smurf(const Smurf& other) = delete;
    virtual ~Smurf() {}

    virtual Smurf& operator=(const Smurf& other) {}
};

} // namespace bar

} // namespace foo
