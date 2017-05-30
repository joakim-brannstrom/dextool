/** @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
 * @date 2017
 * @author Joakim Brännström (joakim.brannstrom@gmx.com)
 *
 * This file contains a test runner specialized for fuzzy testing.
 * The design is inspired from google test.
 * The crucial design goal is to fix the execution order of the tests as to
 * make it possible to extend the fuzzy test suite with more tests without
 * changing how the _current_ data is interpreted. At least for the data that
 * has been used and _actually_ affected behavior.
 */
#ifndef FUZZ_RUNNER_HPP
#define FUZZ_RUNNER_HPP
#include "dextool/i_fuzz.hpp"
#include "dextool/internal_extern.hpp"

#include <algorithm>
#include <iostream>
#include <vector>

namespace dextool {
class FuzzFactory {
public:
    virtual ~FuzzFactory() {}

    virtual Fuzz* make() = 0;

    /** The registered test cases are executed in the ascending order by the
     * sequence.
     * It ensures an unchanged execution order when new test cases are added.
     */
    virtual int64_t sequence() = 0;
};

/// Runner for all registered fuzz tests.
class FuzzRunner {
public:
    typedef std::vector<FuzzFactory*> FuzzCases;

    FuzzRunner() {}
    ~FuzzRunner() {}

    void run() {
        std::sort(fuzz_cases.begin(), fuzz_cases.end(), FuzzRunner::cmp_sequence<FuzzFactory*>);

        for (FuzzCases::iterator it = fuzz_cases.begin(); it != fuzz_cases.end(); ++it) {
            Fuzz* instance = (*it)->make();
            instance->run();
            delete instance;
        }
    }

    void put(FuzzFactory* case_) {
        fuzz_cases.push_back(case_);
    }

private:
    template<typename T>
    static bool cmp_sequence(T l, T r) {
        return l->sequence() < r->sequence();
    }

    FuzzCases fuzz_cases;
};

template<typename T, int64_t seq_>
struct FuzzFactoryImpl : public FuzzFactory {
    FuzzFactoryImpl() {
        get_fuzz_runner().put(this);
    }

    Fuzz* make() {
        return new T;
    }

    virtual int64_t sequence() {
        return seq_;
    }
};

} //NS:dextool
#endif // FUZZ_RUNNER_HPP
