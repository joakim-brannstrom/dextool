
#ifndef DEXTOOL_MUTANT_COV_INCL_GUARD
#pragma GCC diagnostic ignored "-Wunused-macros"
#define DEXTOOL_MUTANT_COV_INCL_GUARD

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static char* gDEXTOOL_COVMAP;
static int gDEXTOOL_COVMAP_FD;

__attribute__((constructor, weak)) void dextool_init_covmap(void) {
    const char* cov_map_file;
    int fd;
    struct stat sb;
    char* addr;

    gDEXTOOL_COVMAP = 0;

    cov_map_file = getenv("DEXTOOL_COVMAP");
    if (cov_map_file == NULL)
        return;
    fd = open(cov_map_file, O_RDWR);
    if (fd == -1)
        return;
    if (fstat(fd, &sb) == -1)
        return;
    addr = (char*)mmap(NULL, sb.st_size, PROT_WRITE, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED)
        return;
    gDEXTOOL_COVMAP = addr;
    gDEXTOOL_COVMAP_FD = fd;
    *(gDEXTOOL_COVMAP) = 1; /* successfully initialized */
}

__attribute__((weak)) void dextool_cov(unsigned int x) {
    if (gDEXTOOL_COVMAP == NULL)
        return;
    *(gDEXTOOL_COVMAP + x) = 1;
}

#endif /* DEXTOOL_MUTANT_COV_INCL_GUARD */

