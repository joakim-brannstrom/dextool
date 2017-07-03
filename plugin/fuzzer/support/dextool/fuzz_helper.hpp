/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// Support library for the dextool plugin Fuzzer.
/// Part of the intention of this helper functions is to have most of the code
/// in a support library that is easier to maintain than as generated code.
/// The implementation try to avoid the C++ stdlib because it may not be
/// available on all systems.
#ifndef FUZZ_HELPER_HPP
#define FUZZ_HELPER_HPP
#include "dextool/internal_extern.hpp"

#include <unistd.h>

namespace dextool {

/// Read all data on stdin and store in data.
void read_stdin(dextool::RawData& data);

/// Read all data from the file and store in data.
int read_file(dextool::RawData& data, const char* fname);

/// Execute the input files one by one.
void execute_all_input_files_one_by_one(int argc, char** argv, int files_start_at_index, DefaultSource** stdin_src, int runs);

/// Fuzz value with from the source with enough data.
template<typename SourceT, typename T>
void fuzz(SourceT& fuzz_src, T& value) {
    const std::size_t tz = sizeof(T);

    if (fuzz_src.guided.has_bytes(tz)) {
        fuzz_src.guided.fuzz(&value);
    } else {
        fuzz_src.fallback.fuzz(&value);
    }
}

/// Fuzz value with from the source with enough data keeping the value in [lower, upper) range.
/// Note that the range is INCLUSIVE .. EXCLUSIVE.
/// The numbers that are generated are up to but not including upper.
template<typename SourceT, typename T, typename T0, typename T1>
void fuzz_r(SourceT& fuzz_src, T& value, T0 lower, T1 upper) {
    const std::size_t tz = sizeof(T);

    if (fuzz_src.guided.has_bytes(tz)) {
        fuzz_src.guided.fuzz_r(&value, lower, upper);
    } else {
        fuzz_src.fallback.fuzz_r(&value, lower, upper);
    }
}

/// Fuzz buf with data from the the source with enough data.
/// @param len length in elements of buf.
template<typename SourceT, typename T>
void fuzz_buf(SourceT& fuzz_src, size_t len, T* buf) {
    if (fuzz_src.guided.has_bytes(len * sizeof(buf))) {
        fuzz_src.guided.fuzz_buf(len, buf);
    } else {
        fuzz_src.fallback.fuzz_buf(len, buf);
    }
}

/// Return sz bytes from the source with enough data.
template<typename T, typename SourceT>
T fuzz_instance(SourceT& fuzz_src) {
    const std::size_t tz = sizeof(T);
    T value;

    if (fuzz_src.guided.has_bytes(tz)) {
        fuzz_src.guided.fuzz(&value);
    } else {
        fuzz_src.fallback.fuzz(&value);
    }

    return value;
}

// convenient functions using the default data source.

template<typename T>
void fuzz(T& value) {
    fuzz(dextool::get_default_source(), value);
}

template<typename T, typename T0, typename T1>
void fuzz_r(T& value, T0 lower, T1 upper) {
    fuzz_r(dextool::get_default_source(), value, lower, upper);
}

template<typename T>
void fuzz_buf(size_t len, T* buf) {
    fuzz_buf(dextool::get_default_source(), len, buf);
}

template<typename T>
T fuzz_instance() {
    return fuzz_instance<T>(dextool::get_default_source());
}

} // NS: dextool

#endif // FUZZ_HELPER_HPP
