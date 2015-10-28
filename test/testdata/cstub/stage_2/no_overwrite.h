// The error in this file is expected to be suppressed by no_overwrite_pre_includes.hpp
// This file in turn suppresses the error in no_overwrite_post_includes.hpp

#ifndef NO_OVERWRITE_H
#define NO_OVERWRITE_H

void func();

#ifndef PRE_INCLUDES
#error "not suppressed by pre_includes"
#endif

#define POST_INCLUDES 1

#endif // NO_OVERWRITE_H
