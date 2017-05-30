/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#ifndef DATA_SOURCE_HPP
#define DATA_SOURCE_HPP

#include <unistd.h>
#include <assert.h>
#include <string.h>

#include <limits>

#include "dextool/types.hpp"
#include "dextool/pcg_basic.h"

namespace dextool {

/// A source of infinite data to use to fuzz when the guided source is ouf ot data.
struct ZeroSource {
    /// Fuzz value with bytes derived from the sizeof the type.
    /// @param value destinatin address to write data to.
    template<typename T>
    void fuzz(T* value) {
        const std::size_t tz = sizeof(T);

        uint8_t* dst = reinterpret_cast<uint8_t*>(value);
        memset(dst, 0, tz);
    }
};

/// A source of infinite data to use to fuzz when the guided source is ouf ot data.
struct RandomSource {
    RandomSource(uint64_t seed) {
        if (seed == 0) {
            uint64_t v[2] = PCG32_INITIALIZER;
            pcg32_srandom_r(&rng, v[0], v[1]);
        } else {
            pcg32_srandom_r(&rng, seed, reinterpret_cast<intptr_t>(&rng));
        }
    }

    template<typename T, typename T0, typename T1>
    void fuzz_r(T* value, T0 lower, T1 upper) {
        // guard against stupidity
        T l = std::min(lower, upper);
        T u = std::max(lower, upper);

        if (l == u) {
            // more stupidity but makes it easier in the generic case.
            *value = l;
        } else if (sizeof(T) <= sizeof(uint32_t)) {
            *value = l + pcg32_boundedrand_r(&rng, u - l);
        } else {
            // assuming it is 64bit or bigger. not perfect but works for 64
            // bit.

            T bound = u - l;
            T threshold = -bound % bound;
            for (;;) {
                T r = static_cast<uint64_t>(pcg32_random_r(&rng)) << 32
                      | static_cast<uint64_t>(pcg32_random_r(&rng));
                if (r >= threshold) {
                    *value = l + (r % bound);
                    return;
                }
            }
        }
    }

    /// Fuzz value with bytes derived from the sizeof the type.
    /// @param value destinatin address to write data to.
    template<typename T>
    void fuzz(T* value) {
        const std::size_t tz = sizeof(T);
        uint8_t* dst = reinterpret_cast<uint8_t*>(value);
        this->fuzz_buf(tz, dst);
    }

    /// Fill the buffer with a random value and increment from it.
    /// Too slow when completely randomising the buffer so blasting the buffer
    /// with one random byte.
    template<typename T>
    void fuzz_buf(size_t len, T* buf) {
        const std::size_t tz = sizeof(T);
        const std::size_t bytes = tz * len;

        uint32_t base = pcg32_random_r(&rng);

        uint8_t* dst = reinterpret_cast<uint8_t*>(buf);
        memset(dst, base, bytes);
    }

private:
    pcg32_random_t rng;
};

/// A source of guided data derived from a type that _behaves_ like std::vector containing bytes.
template<typename DataT>
struct GuidedSource {
    DataT& data;

    GuidedSource(DataT& d) : data(d) {}

    bool has_bytes(size_t sz) {
        return sz < data.size();
    }

    /** Fuzz value with bytes derived from the sizeof the type.
     *
     * Assuming that the guided data source has O(n) when shrkinging from the
     * front and O(1) when from the back. Thus the implementation uses data
     * from the end.
     *
     * @param value destinatin address to write data to.
     */
    template<typename T>
    void fuzz(T* value) {
        const std::size_t tz = sizeof(T);

        assert(tz < data.size());

        uint8_t* dst = reinterpret_cast<uint8_t*>(value);
        this->fuzz_buf(tz, dst);
    }

    template<typename T, typename T0, typename T1>
    void fuzz_r(T* value, T0 lower, T1 upper) {
        const std::size_t tz = sizeof(T);

        assert(tz < data.size());

        // guard against stupidity
        T l = std::min(lower, upper);
        T u = std::max(lower, upper);

        if (l == u) {
            // more stupidity but makes it easier in the generic case.
            *value = l;
            return;
        }

        T r;
        this->fuzz_buf(tz, reinterpret_cast<uint8_t*>(&r));

        T bound = u - l;
        r = l + (r % bound);
        // can't use std::abs because of a zillion of warnings
        if (l >= 0 && r < 0) {
            r = -r;
        }

        *value = r;
    }

    template<typename T>
    void fuzz_buf(size_t len, T* buf) {
        const std::size_t tz = sizeof(T);
        const std::size_t bytes = tz * len;

        assert(bytes < data.size());

        uint8_t* dst = reinterpret_cast<uint8_t*>(buf);
        uint8_t* cur = &data[data.size() - 1] - bytes;

        mempcpy(dst, cur, bytes);
        data.erase(data.end() - bytes, data.end());
    }
};

struct DefaultSource {
    typedef dextool::RawData GuidedType;
    typedef dextool::RandomSource RandomSource;

    /// A source of data that is guided by the fuzzer.
    dextool::GuidedSource<GuidedType> guided;

    /// Fallback data source that can generate an infinite amount of data.
    dextool::RandomSource fallback;

    DefaultSource(GuidedType& guide_data) : guided(guide_data), fallback(0) {
        uint64_t seed = 0;

        if (guided.has_bytes(sizeof(seed))) {
            guided.fuzz(&seed);
        }

        fallback = RandomSource(seed);
    }
};

} // NS: dextool

#endif // DATA_SOURCE_HPP
