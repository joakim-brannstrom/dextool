/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
//
// This test the preamble for mutants that it works as expected

#include <assert.h>
#include <fcntl.h>
#include <iostream>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define start_test()                                                                               \
    do {                                                                                           \
        std::cout << " # " << __func__ << "\t\t" << __FILE__ << ":" << __LINE__ << std::endl;      \
    } while (0)
#define msg(x...)                                                                                  \
    do {                                                                                           \
        std::cout << __FILE__ << ":" << __LINE__ << " " << x << std::endl;                         \
    } while (0)

#include "coverage_mmap.c"

static void dextool_deinit_covmap(void) {
    struct stat sb;
    if (fstat(gDEXTOOL_COVMAP_FD, &sb) == -1)
        return;

    munmap(gDEXTOOL_COVMAP, sb.st_size);
    close(gDEXTOOL_COVMAP_FD);

    gDEXTOOL_COVMAP = NULL;
    gDEXTOOL_COVMAP_FD = -1;
}

const char* EnvKey = "DEXTOOL_COVMAP";
const char* dummy = "dummy_test_file.bin";

void set_env_covmap(const char* fname) {
    char* s = new char[1024];
    sprintf(s, "%s=%s", EnvKey, fname);
    assert(putenv(s) == 0);
}

int setup_covmap_file(const char* fname) {
    int fd = open(dummy, O_WRONLY | O_CREAT, S_IWUSR | S_IRUSR);
    assert(fd != -1);
    char buf[1];
    for (int i = 0; i < 10; ++i)
        write(fd, &buf, 1);
    return fd;
}

void test_write() {
    start_test();

    msg("Creating coverage map " << dummy);

    msg("Setting env");
    set_env_covmap(dummy);
    int fd = setup_covmap_file(dummy);

    msg("Let init run");
    dextool_init_covmap();
    assert(gDEXTOOL_COVMAP != 0);

    msg("Use instrument function");
    dextool_cov(1);

    dextool_deinit_covmap();
}

void test_read_write() {
    start_test();

    msg("Creating coverage map " << dummy);

    msg("Setting env");
    set_env_covmap(dummy);
    int fd = setup_covmap_file(dummy);

    msg("Let init run");
    dextool_init_covmap();
    assert(gDEXTOOL_COVMAP != 0);

    msg("Use instrument function");
    dextool_cov(1);
    dextool_cov(3);
    dextool_cov(5);

    dextool_deinit_covmap();

    msg("Read what was written");
    char buf[1024];
    fd = open(dummy, O_RDONLY, S_IWUSR | S_IRUSR);
    ssize_t r = read(fd, &buf, 10);
    assert(r != -1);
    assert(buf[0] == 1);
    assert(buf[1] == 1);
    assert(buf[2] == 0);
    assert(buf[3] == 1);

    close(fd);
}

int main(int argc, char** argv) {
    assert(getenv(EnvKey) == nullptr);

    unlink(dummy);

    test_write();
    test_read_write();
    return 0;
}
