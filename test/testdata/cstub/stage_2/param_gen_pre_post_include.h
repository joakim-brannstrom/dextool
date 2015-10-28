// Expecting generation of pre and post includes
#ifndef PARAM_GEN_PRE_POST_INCLUDE_H
#define PARAM_GEN_PRE_POST_INCLUDE_H

void func();

#ifdef __cplusplus
#error "__cplusplus not undefined by standard template"
#endif

#endif // PARAM_GEN_PRE_POST_INCLUDE_H
