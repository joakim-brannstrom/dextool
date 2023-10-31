
#ifndef DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#pragma GCC diagnostic ignored "-Wunused-macros"
#define DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#include <stdlib.h>

#ifdef DEXTOOL_STRONG_ATTR
#define DEXTOOL_ATTR
#else
#define DEXTOOL_ATTR __attribute__((weak))
#endif

static unsigned int gDEXTOOL_MUTID_ISINIT = 0;
static unsigned int gDEXTOOL_MUTID = 0;

DEXTOOL_ATTR void dextool_init_mutid(void) {
    const char* c;

    c = getenv("DEXTOOL_MUTID");
    if (c == NULL) {
        gDEXTOOL_MUTID_ISINIT = 1;
        return;
    }

    unsigned int id = 0;
    for (; *c != '\0'; ++c) {
        const unsigned int n = *c - '0';
        if (n > 9) {
            id = 0;
            break;
        }
        id = id * 10u + n;
    }
    gDEXTOOL_MUTID = id;
    gDEXTOOL_MUTID_ISINIT = 1;
}

#pragma GCC diagnostic ignored "-Wsuggest-attribute=pure"
DEXTOOL_ATTR unsigned int dextool_get_mutid(void) {
    if (gDEXTOOL_MUTID_ISINIT == 0)
        dextool_init_mutid();
    return gDEXTOOL_MUTID;
}

#endif /* DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD */

