#ifndef DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#define DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#include <stdlib.h>

static unsigned int gDEXTOOL_MUTID;

__attribute__((constructor)) static void init_dextool_mutid(void) {
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

#endif /* DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD */
