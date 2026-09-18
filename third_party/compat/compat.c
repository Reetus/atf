/* Shims for gnulib modules that atf replaces with the C library.

   time_rz: the vendored parser takes a timezone_t argument so it can honor
     TZ strings. Like gnulib's time_rz, a zone is stored by name and the TZ
     environment is only touched when it differs from the zone in use, then
     restored. The common case -- TZ set by the user, tzalloc(getenv("TZ")) --
     does not modify the environment at all, which also keeps the parser's
     pointer into the environment valid.
   nstrftime: debug output only, maps to strftime. */

#include <config.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "strftime.h"

struct tm_zone {
  char *name; /* NULL: use the TZ environment as-is */
};

timezone_t
tzalloc (char const *name)
{
  struct tm_zone *tz = malloc (sizeof *tz);
  if (!tz)
    return NULL;
  tz->name = NULL;
  if (name)
    {
      tz->name = strdup (name);
      if (!tz->name)
        {
          free (tz);
          return NULL;
        }
    }
  return tz;
}

void
tzfree (timezone_t tz)
{
  if (tz)
    {
      free (tz->name);
      free (tz);
    }
}

/* True when using TZ as-is already gives the zone NAME. */
static bool
zone_matches_env (char const *name)
{
  char const *env = getenv ("TZ");
  return name ? (env && strcmp (name, env) == 0) : (env == NULL);
}

/* Temporarily switch to NAME (NULL: unset TZ). Returns the previous TZ
   value, to be passed to restore_env, or NULL when nothing was changed. */
static char *
switch_env (char const *name)
{
  char const *env = getenv ("TZ");
  char *saved = env ? strdup (env) : NULL;
  if (env && !saved)
    return NULL;
  if (name)
    setenv ("TZ", name, 1);
  else
    unsetenv ("TZ");
  tzset ();
  return saved;
}

static void
restore_env (char *saved)
{
  if (saved)
    setenv ("TZ", saved, 1);
  else
    unsetenv ("TZ");
  tzset ();
  free (saved);
}

struct tm *
localtime_rz (timezone_t tz, time_t const *t, struct tm *tm)
{
  if (!tz || zone_matches_env (tz->name))
    return localtime_r (t, tm);

  char *saved = switch_env (tz->name);
  struct tm *r = localtime_r (t, tm);
  restore_env (saved);
  return r;
}

time_t
mktime_z (timezone_t tz, struct tm *tm)
{
  if (!tz || zone_matches_env (tz->name))
    return mktime (tm);

  char *saved = switch_env (tz->name);
  time_t r = mktime (tm);
  restore_env (saved);
  return r;
}

size_t
nstrftime (char *s, size_t maxsize, char const *format, struct tm const *tp,
           timezone_t tz, int ns)
{
  (void) tz;
  (void) ns;
  return strftime (s, maxsize, format, tp);
}
