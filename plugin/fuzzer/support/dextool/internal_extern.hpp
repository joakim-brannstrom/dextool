/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
/// This file contains the extern declarations that a user of this lib has to
/// implement.
#ifndef INTERNAL_EXTERN_HPP
#define INTERNAL_EXTERN_HPP

namespace dextool {

struct DefaultSource;
class FuzzRunner;
struct Context;

/// Access the global, default source of fuzz data.
/// Must be implemented by the user of dextool if any fuzz case uses the source.
/// Could be placed in e.g in the same file as the main routine.
extern DefaultSource& get_default_source();

/// Access the global runner.
/// Must be implemented by the user of dextool.
/// Could be placed in e.g in the same file as the main routine.
extern FuzzRunner& get_fuzz_runner();

} // NS: dextool

#endif // INTERNAL_EXTERN_HPP
