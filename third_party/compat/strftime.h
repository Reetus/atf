/* nstrftime shim: the vendored parser only calls nstrftime() for its
   PARSE_DATETIME_DEBUG output, which atf never enables. timezone_t comes
   from third_party/parse-datetime/config.h, which every includer must have
   included first. */

#ifndef ATF_STRFTIME_H
#define ATF_STRFTIME_H

#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

size_t nstrftime (char *restrict, size_t, char const *, struct tm const *,
                  timezone_t, int);

#ifdef __cplusplus
}
#endif

#endif
