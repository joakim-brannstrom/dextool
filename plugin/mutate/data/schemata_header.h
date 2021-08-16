
#ifndef DEXTOOL_MUTANT_SCHEMATA_HDR_INCL_GUARD
#pragma GCC diagnostic ignored "-Wunused-macros"
#define DEXTOOL_MUTANT_SCHEMATA_HDR_INCL_GUARD

extern void dextool_init_mutid(void);
extern unsigned int dextool_get_mutid(void);

#ifndef unlikely
/* __builtin_expect added in gcc <4.0 */
#if (__GNUC__ > 4)
#define unlikely(x) __builtin_expect(!!(x), 0)
#else
#define unlikely(x) (x)
#endif
#endif

#endif /* DEXTOOL_MUTANT_SCHEMATA_HDR_INCL_GUARD */
