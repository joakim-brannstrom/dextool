#ifndef NS_MERGE_HPP
#define NS_MERGE_HPP
namespace ns1 {

void fun();

int gun;

class Wun {
public:
    virtual ~Wun() {}
    virtual void fun();
};

} // NS: ns1

namespace ns1 {

void batman();

int robin;

class Joker {
public:
    virtual ~Joker() {}
    virtual void laugh();
};

} // NS: ns1
#endif // NS_MERGE_HPP
