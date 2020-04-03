#ifndef DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#define DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t gDEXTOOL_MUTID;

__attribute__((constructor)) static void init_dextool_mutid(void) {
    gDEXTOOL_MUTID = 0;
    const char* e = getenv("DEXTOOL_MUTID");
    if (e != NULL) {
        sscanf(e, "%lu", &gDEXTOOL_MUTID);
    }
}

#endif /* DEXTOOL_MUTANT_SCHEMATA_INCL_GUARD */
