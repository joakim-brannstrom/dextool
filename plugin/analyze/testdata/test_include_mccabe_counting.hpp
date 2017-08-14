#ifndef TEST_INCLUDE_MCCABE_COUNTING_HPP
#define TEST_INCLUDE_MCCABE_COUNTING_HPP

void not_counted();

class InlineCounter {
public:
    InlineCounter() {}
    virtual ~InlineCounter() {}

    void inline_counted() {}

private:
    InlineCounter(const InlineCounter& other);
    InlineCounter& operator=(const InlineCounter& other);
};

#endif // TEST_INCLUDE_MCCABE_COUNTING_HPP
