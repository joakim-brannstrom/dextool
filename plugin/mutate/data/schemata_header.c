
#ifndef DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#pragma GCC diagnostic ignored "-Wunused-macros"
#define DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#include <stdlib.h>

static unsigned int gDEXTOOL_MUTID;

__attribute__((constructor, weak)) void dextool_init_mutid(void) {
    gDEXTOOL_MUTID = 0;
    const char* c = getenv("DEXTOOL_MUTID");
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
__attribute__((weak)) unsigned int dextool_get_mutid__(void) { return gDEXTOOL_MUTID; }

#endif /* DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD */

