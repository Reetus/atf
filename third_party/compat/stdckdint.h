/* Minimal C23 <stdckdint.h> for compilers that lack it (GCC < 14).

   atf builds only with GCC/Clang on Linux, so the overflow builtins are
   always available. This header intentionally implements just the three
   interfaces the vendored parser uses. */

#ifndef ATF_STDCKDINT_H
#define ATF_STDCKDINT_H

#include <stdbool.h>

#define ckd_add(result, a, b) __builtin_add_overflow ((a), (b), (result))
#define ckd_sub(result, a, b) __builtin_sub_overflow ((a), (b), (result))
#define ckd_mul(result, a, b) __builtin_mul_overflow ((a), (b), (result))

#endif
