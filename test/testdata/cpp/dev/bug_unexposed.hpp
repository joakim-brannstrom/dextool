// Unexposed results in two bugs:
// bug 1: Must validate that the type is valid before recursively calling translateType
// bug 2: infinite loop of translateUnexposed

#ifndef BUG_UNEXPOSED_HPP
#define BUG_UNEXPOSED_HPP

template<typename T>
class Exposed {
public:
    explicit Exposed() {}

    class Unexposed;
};

template <typename T>
class Exposed<T>::Unexposed {
public:
    explicit Unexposed(Exposed<T>& x);
};

#endif // BUG_UNEXPOSED_HPP
