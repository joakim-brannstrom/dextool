#ifndef IFS1_HPP
#define IFS1_HPP
#include "ifs2.hpp"
#include "ifs3.hpp"

/// Description
class Ifs1 : public Ifs2 {
public:
    Ifs1() {}
    virtual ~Ifs1() {}

    virtual void run() = 0;

    virtual Ifs2& get_ifc2() = 0;
    virtual Ifs3& get_ifc3() = 0;
};
#endif // IFS1_HPP
