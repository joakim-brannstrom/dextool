/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "dextool/dextool.hpp"

#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>

#include <iostream>

// Used to avoid repeating error checking boilerplate. If cond is false, a
// fatal error has occured in the program. In this event print error_message
// to stderr and abort(). Otherwise do nothing. Note that setting
// AFL_DRIVER_STDERR_DUPLICATE_FILENAME may cause error_message to be appended
// to the file as well, if the error occurs after the duplication is performed.
#define CHECK_ERROR(cond, error_message)  \
    if (!(cond)) {                        \
        fprintf(stderr, (error_message)); \
        abort();                          \
    }

namespace dextool {

namespace {

void read_stream(dextool::RawData& data, int fd) {
    const ssize_t BUF_SIZE = 4096;
    std::vector<uint8_t> buf(BUF_SIZE);

    for (;;) {
        ssize_t status = read(fd, buf.data(), BUF_SIZE);

        if (status == 0) {
            return;
        } else if (status < 0) {
            // error handling
            return;
        }

        data.insert(data.end(), buf.begin(), buf.begin() + status);
    }
}

} // NS:

void read_stdin(dextool::RawData& data) {
    read_stream(data, 0);
}

int read_file(dextool::RawData& data, const char* fname) {
    int fdin = open(fname, 0, O_RDONLY);

    if (fdin == -1) {
        return -1;
    }

    read_stream(data, fdin);
    close(fdin);

    return 0;
}

FuzzRunner& get_fuzz_runner() {
    static FuzzRunner runner;
    return runner;
}

void execute_all_input_files_one_by_one(int argc, char** argv, int files_start_at_index, DefaultSource** stdin_src, int rerun) {
    dextool::DefaultSource::GuidedType guide_data;

    struct timeval slowest_unit_time;
    timerclear(&slowest_unit_time);
    int slowest_idx = 0;

    for (int runs = 0; runs < rerun; ++runs) {
        for (int i = files_start_at_index; i < argc; ++i) {
            int status = dextool::read_file(guide_data, argv[i]);
            if (status == -1) {
                std::cout << "  Unable to read: " << argv[i] << "\n";
                continue;
            }

            *stdin_src = new dextool::DefaultSource(guide_data);

            std::cerr << "Running: " << argv[i] << " (" << guide_data.size() << " bytes)\n";

            struct timeval unit_start_time;
            CHECK_ERROR(gettimeofday(&unit_start_time, NULL) == 0,
                        "Calling gettimeofday failed");

            dextool::get_fuzz_runner().run();

            struct timeval unit_stop_time;
            CHECK_ERROR(gettimeofday(&unit_stop_time, NULL) == 0,
                        "Calling gettimeofday failed");

            // Update slowest_unit_time_secs if we see a new max.
            struct timeval res;
            timersub(&unit_stop_time, &unit_start_time, &res);
            if (timercmp(&res, &slowest_unit_time, >)) {
                slowest_unit_time = res;
                slowest_idx = i;
            }

            delete *stdin_src;
            guide_data.clear();
        }
    }

    if (slowest_idx > 0) {
        std::cerr << argv[0] << ": successfully executed\n";
        std::cerr << "Slowest test file: " << argv[slowest_idx] << " (" << slowest_unit_time.tv_sec << "s " << slowest_unit_time.tv_usec << "ms)" << "\n";
    } else {
        std::cerr << argv[0] << ": failed executed\n";
        std::cerr << "No input files provided\n";
    }
}

} // NS: dextool
