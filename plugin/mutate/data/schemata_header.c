
#ifndef DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#pragma GCC diagnostic ignored "-Wunused-macros"
#define DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#include <stdlib.h>

#ifdef DEXTOOL_STRONG_ATTR
#define DEXTOOL_CTOR_ATTR __attribute__((constructor))
#define DEXTOOL_ATTR
#else
#define DEXTOOL_CTOR_ATTR __attribute__((constructor, weak))
#define DEXTOOL_ATTR __attribute__((weak))
#endif

static unsigned int gDEXTOOL_MUTID;

DEXTOOL_CTOR_ATTR void dextool_init_mutid(void) {
    gDEXTOOL_MUTID = 0;
    const char* c;

    c = getenv("DEXTOOL_MUTID");
    if (c == NULL)
        return;
    for (; *c != '\0'; ++c) {
        const unsigned int n = *c - '0';
        if (n > 9) {
            gDEXTOOL_MUTID = 0;
            break;
        }
        gDEXTOOL_MUTID = gDEXTOOL_MUTID * 10u + n;
    }
}

#pragma GCC diagnostic ignored "-Wsuggest-attribute=pure"
DEXTOOL_ATTR unsigned int dextool_get_mutid(void) { return gDEXTOOL_MUTID; }

#endif /* DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD */

