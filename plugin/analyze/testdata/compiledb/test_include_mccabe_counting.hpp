#ifndef TEST_INCLUDE_MCCABE_COUNTING_HPP
#define TEST_INCLUDE_MCCABE_COUNTING_HPP

void not_counted();

class InlineCounter {
public:
    InlineCounter() = default;
    InlineCounter(const InlineCounter& other) = delete;
    InlineCounter& operator=(const InlineCounter& other) = delete;
    virtual ~InlineCounter();

    void inline_counted() {}
};

#endif // TEST_INCLUDE_MCCABE_COUNTING_HPP
