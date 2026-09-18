// atf - run a command at a specified time, in the foreground.
//
// Waits in the foreground until TIME, then runs COMMAND (or just exits, so it
// can be used like `sleep` in a sequence of commands). TIME is parsed by the
// gnulib parse-datetime parser, which accepts the same loose grammar as
// GNU `date -d` and `at`: ISO 8601, time-of-day, explicit UTC offsets,
// relative expressions, "tomorrow", "@epoch", "now", and so on.

#include <cctype>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <signal.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#ifndef ATF_VERSION
#define ATF_VERSION "0.1.0"
#endif

extern "C" bool parse_datetime (struct timespec *, char const *,
                                struct timespec const *);

namespace {

struct Options {
  bool quiet = false;
  bool print_only = false;
  bool force = false;
  bool pretty = false;
};

volatile sig_atomic_t g_signal = 0;

void
handle_signal (int sig)
{
  g_signal = sig;
}

void
install_signal_handlers ()
{
  struct sigaction sa;
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = handle_signal;
  sigemptyset (&sa.sa_mask);
  sa.sa_flags = 0;
  sigaction (SIGINT, &sa, nullptr);
  sigaction (SIGTERM, &sa, nullptr);
  sigaction (SIGHUP, &sa, nullptr);
}

void
usage (FILE *out)
{
  fputs (
    "Usage: atf [OPTION]... TIME [-- COMMAND [ARG]...]\n"
    "Wait until TIME, then run COMMAND; with no COMMAND, just exit.\n"
    "\n"
    "TIME accepts the same loose grammar as GNU date -d / at, e.g.\n"
    "  23:00, 0200, midnight       today, or tomorrow if already past\n"
    "  :55                         next time the clock reaches :55\n"
    "  '2026-10-26 23:00+07:00'    explicit UTC offset\n"
    "  2026-10-26T23:00:00Z        ISO 8601\n"
    "  'tomorrow 23:00'            relative words\n"
    "  '+2 hours'                  relative to now\n"
    "  @1800000000                 seconds since the epoch\n"
    "  now                         run immediately\n"
    "\n"
    "A TIME with no date part that is already past rolls over to the next\n"
    "day; an explicitly dated time in the past is an error (see -f).\n"
    "\n"
    "TIME is interpreted in the TZ environment variable's time zone unless\n"
    "it carries an explicit offset: TZ=Asia/Bangkok atf 23:00 -- cmd.\n"
    "\n"
    "  -q, --quiet       do not print the status line\n"
    "  -p, --print       print the target Unix time and exit\n"
    "  -f, --force       if TIME is in the past, run immediately\n"
    "  -P, --pretty      live countdown bar on a terminal (alias --progress;\n"
    "                    falls back to the plain status line off-terminal)\n"
    "  -h, --help        display this help and exit\n"
    "  -v, --version     output version information and exit\n"
    "\n"
    "COMMAND is executed directly (execvp), not through a shell; use\n"
    "-- sh -c '...' if shell syntax is needed. The exit status is that of\n"
    "COMMAND, 127 if it cannot be found, or 0 when there is no COMMAND.\n",
    out);
}

std::string
trim (std::string s)
{
  size_t b = 0, e = s.size ();
  while (b < e && isspace ((unsigned char) s[b]))
    b++;
  while (e > b && isspace ((unsigned char) s[e - 1]))
    e--;
  return s.substr (b, e - b);
}

std::string
lower (std::string s)
{
  for (char &c : s)
    c = (char) tolower ((unsigned char) c);
  return s;
}

// True when TIME consists only of clock-time tokens: "23:00", "4pm",
// "0200" (military), "midnight", "14:00:00.5". Such a time in the past
// means the next day, matching at(1).
bool
is_time_of_day (std::string s)
{
  s = lower (trim (s));
  if (s.empty ())
    return false;

  size_t i = 0;
  while (i < s.size ())
    {
      while (i < s.size () && isspace ((unsigned char) s[i]))
        i++;
      if (i == s.size ())
        break;
      size_t start = i;
      while (i < s.size () && !isspace ((unsigned char) s[i]))
        i++;
      std::string w = s.substr (start, i - start);

      if (w == "am" || w == "pm" || w == "a.m." || w == "p.m."
          || w == "o'clock" || w == "oclock" || w == "noon"
          || w == "midnight")
        continue;

      for (char c : w)
        if (!isdigit ((unsigned char) c) && c != ':' && c != '.')
          return false;
    }
  return true;
}

struct timespec now_timespec ();

// Parse ":MM" or ":MM:SS" as the next time the clock reaches that minute
// (and second) within the next hour, in the TZ environment's zone. This
// shorthand is an atf extension; the date grammar cannot express it.
bool
next_minute_of_hour (std::string s, struct timespec *out)
{
  s = trim (s);
  if (s.empty () || s[0] != ':')
    return false;

  size_t i = 1;
  size_t start = i;
  int minute = 0;
  while (i < s.size () && isdigit ((unsigned char) s[i]))
    {
      minute = minute * 10 + (s[i] - '0');
      i++;
    }
  if (i == start || i - start > 2 || minute > 59)
    return false;

  int second = 0;
  if (i < s.size ())
    {
      if (s[i] != ':')
        return false;
      i++;
      start = i;
      while (i < s.size () && isdigit ((unsigned char) s[i]))
        {
          second = second * 10 + (s[i] - '0');
          i++;
        }
      if (i == start || i - start > 2 || second > 59)
        return false;
    }
  if (i != s.size ())
    return false;

  struct timespec now = now_timespec ();
  struct tm tm;
  if (!localtime_r (&now.tv_sec, &tm))
    return false;

  tm.tm_min = minute;
  tm.tm_sec = second;
  tm.tm_isdst = -1;
  time_t t = mktime (&tm);
  if (t == (time_t) -1)
    return false;
  if ((long long) t <= (long long) now.tv_sec)
    {
      tm.tm_hour++;
      tm.tm_isdst = -1;
      t = mktime (&tm);
      if (t == (time_t) -1)
        return false;
    }

  out->tv_sec = t;
  out->tv_nsec = 0;
  return true;
}

int
compare_timespec (struct timespec a, struct timespec b)
{
  if (a.tv_sec != b.tv_sec)
    return a.tv_sec < b.tv_sec ? -1 : 1;
  if (a.tv_nsec != b.tv_nsec)
    return a.tv_nsec < b.tv_nsec ? -1 : 1;
  return 0;
}

struct timespec
now_timespec ()
{
  struct timespec ts;
  clock_gettime (CLOCK_REALTIME, &ts);
  return ts;
}

std::string
human_time (time_t t)
{
  struct tm tm;
  char buf[128];
  if (!localtime_r (&t, &tm) || !strftime (buf, sizeof buf,
                                           "%a %b %e %H:%M:%S %Z %Y", &tm))
    {
      snprintf (buf, sizeof buf, "%lld", (long long) t);
    }
  return buf;
}

std::string
human_duration (long long secs)
{
  if (secs < 0)
    secs = 0;
  long long d = secs / 86400;
  long long h = (secs % 86400) / 3600;
  long long m = (secs % 3600) / 60;
  long long s = secs % 60;
  char buf[128];
  if (d > 0)
    snprintf (buf, sizeof buf, "%lldd %lldh %lldm", d, h, m);
  else if (h > 0)
    snprintf (buf, sizeof buf, "%lldh %lldm %llds", h, m, s);
  else if (m > 0)
    snprintf (buf, sizeof buf, "%lldm %llds", m, s);
  else
    snprintf (buf, sizeof buf, "%llds", s);
  return buf;
}

// Sleep until an absolute wall-clock time. Uses CLOCK_REALTIME with
// TIMER_ABSTIME so NTP steps and suspend/resume are handled by the kernel.
int
wait_until (struct timespec target)
{
  for (;;)
    {
      if (g_signal)
        {
          fprintf (stderr, "atf: interrupted by signal %d\n", (int) g_signal);
          return 128 + (int) g_signal;
        }
      if (compare_timespec (now_timespec (), target) >= 0)
        return 0;
      int r = clock_nanosleep (CLOCK_REALTIME, TIMER_ABSTIME, &target, nullptr);
      if (r != 0 && r != EINTR)
        {
          errno = r;
          perror ("atf: clock_nanosleep");
          return 2;
        }
    }
}

int
terminal_width (int fd)
{
  struct winsize ws;
  if (ioctl (fd, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0)
    return ws.ws_col;
  return 80;
}

bool
locale_utf8 ()
{
  char const *env = getenv ("LC_ALL");
  if (!env || !*env)
    env = getenv ("LC_CTYPE");
  if (!env || !*env)
    env = getenv ("LANG");
  if (!env)
    return false;
  std::string s = lower (env);
  return s.find ("utf-8") != std::string::npos
         || s.find ("utf8") != std::string::npos;
}

void
erase_progress ()
{
  fputs ("\r\033[K", stderr);
  fflush (stderr);
}

// Redraw the single progress line, overwriting the previous one with \r.
void
draw_progress (struct timespec start, struct timespec target,
               struct timespec now, bool utf8)
{
  long long total_ns = (long long) (target.tv_sec - start.tv_sec) * 1000000000LL
                       + (target.tv_nsec - start.tv_nsec);
  long long done_ns = (long long) (now.tv_sec - start.tv_sec) * 1000000000LL
                      + (now.tv_nsec - start.tv_nsec);
  int pct = total_ns > 0 ? (int) (done_ns * 100 / total_ns) : 100;
  if (pct < 0)
    pct = 0;
  if (pct > 100)
    pct = 100;

  long long remain_ns = (long long) (target.tv_sec - now.tv_sec) * 1000000000LL
                        + (target.tv_nsec - now.tv_nsec);
  long long remain = (remain_ns + 999999999LL) / 1000000000LL;

  std::string suffix = " " + std::to_string (pct) + "% "
                       + human_duration (remain);
  std::string prefix = "atf: ";

  int barw = terminal_width (STDERR_FILENO)
             - (int) (prefix.size () + suffix.size ()) - 3;
  if (barw > 30)
    barw = 30;
  if (barw < 5)
    barw = 0;

  std::string bar;
  if (barw > 0)
    {
      int filled = (int) ((long long) barw * pct / 100);
      char const *full = utf8 ? "\u2588" : "#";
      char const *empty = utf8 ? "\u2591" : "-";
      bar.reserve ((size_t) barw * 4 + 2);
      bar = "[";
      for (int i = 0; i < barw; i++)
        bar += (i < filled ? full : empty);
      bar += "]";
    }

  fprintf (stderr, "\r\033[K%s%s%s", prefix.c_str (), bar.c_str (),
           suffix.c_str ());
  fflush (stderr);
}

// Wait like wait_until, but redraw a progress line once per second.
int
wait_until_pretty (struct timespec start, struct timespec target)
{
  bool utf8 = locale_utf8 ();
  for (;;)
    {
      if (g_signal)
        {
          erase_progress ();
          fprintf (stderr, "atf: interrupted by signal %d\n", (int) g_signal);
          return 128 + (int) g_signal;
        }
      struct timespec now = now_timespec ();
      if (compare_timespec (now, target) >= 0)
        break;
      draw_progress (start, target, now, utf8);
      struct timespec tick = now;
      tick.tv_sec++;
      if (compare_timespec (tick, target) > 0)
        tick = target;
      int r = clock_nanosleep (CLOCK_REALTIME, TIMER_ABSTIME, &tick, nullptr);
      if (r != 0 && r != EINTR)
        {
          erase_progress ();
          errno = r;
          perror ("atf: clock_nanosleep");
          return 2;
        }
    }
  erase_progress ();
  return 0;
}

} // namespace

int
main (int argc, char **argv)
{
  install_signal_handlers ();

  Options opt;
  int i = 1;
  for (; i < argc; i++)
    {
      std::string a = argv[i];
      if (a == "--")
        {
          i++;
          break;
        }
      if (a.empty () || a[0] != '-' || a == "-")
        break;
      if (a == "-q" || a == "--quiet")
        opt.quiet = true;
      else if (a == "-p" || a == "--print")
        opt.print_only = true;
      else if (a == "-f" || a == "--force")
        opt.force = true;
      else if (a == "-P" || a == "--pretty" || a == "--progress")
        opt.pretty = true;
      else if (a == "-h" || a == "--help")
        {
          usage (stdout);
          return 0;
        }
      else if (a == "-v" || a == "--version")
        {
          printf ("atf %s (parse-datetime from GNU coreutils 9.4)\n",
                  ATF_VERSION);
          return 0;
        }
      else
        {
          fprintf (stderr, "atf: unknown option '%s'\n", a.c_str ());
          usage (stderr);
          return 2;
        }
    }

  std::string time_str;
  int cmd_index = argc;
  for (int j = i; j < argc; j++)
    {
      if (strcmp (argv[j], "--") == 0)
        {
          cmd_index = j + 1;
          break;
        }
      if (!time_str.empty ())
        time_str += ' ';
      time_str += argv[j];
    }

  if (time_str.empty ())
    {
      fprintf (stderr, "atf: missing TIME\n");
      usage (stderr);
      return 2;
    }

  struct timespec target;
  if (!next_minute_of_hour (time_str, &target)
      && !parse_datetime (&target, time_str.c_str (), nullptr))
    {
      fprintf (stderr, "atf: cannot parse time '%s'\n", time_str.c_str ());
      return 2;
    }

  struct timespec now = now_timespec ();
  bool immediate = false;
  if (compare_timespec (target, now) <= 0)
    {
      // A relative expression like "now" lands a hair in the past because
      // parsing takes time; treat that as immediate.
      long long late_ns = (long long) (now.tv_sec - target.tv_sec) * 1000000000
                          + (now.tv_nsec - target.tv_nsec);
      if (late_ns <= 1000000000LL)
        immediate = true;
      else if (is_time_of_day (time_str))
        {
          std::string next = "tomorrow " + time_str;
          if (!parse_datetime (&target, next.c_str (), nullptr)
              || compare_timespec (target, now) <= 0)
            {
              fprintf (stderr, "atf: cannot determine a future time from '%s'\n",
                       time_str.c_str ());
              return 2;
            }
          if (!opt.quiet)
            fprintf (stderr, "atf: '%s' has passed; using tomorrow\n",
                     time_str.c_str ());
        }
      else if (opt.force)
        immediate = true;
      else
        {
          fprintf (stderr,
                   "atf: '%s' (%s) is in the past; use -f to run now\n",
                   time_str.c_str (), human_time (target.tv_sec).c_str ());
          return 1;
        }
    }

  if (opt.print_only)
    {
      printf ("%lld\n", (long long) target.tv_sec);
      return 0;
    }

  if (!immediate)
    {
      // The progress bar needs a terminal to redraw; off-terminal (logs,
      // pipes) fall back to the single status line.
      bool progress = opt.pretty && !opt.quiet && isatty (STDERR_FILENO);
      if (!opt.quiet && !progress)
        {
          long long secs = (long long) target.tv_sec - (long long) now.tv_sec;
          fprintf (stderr, "atf: waiting until %s (in %s)\n",
                   human_time (target.tv_sec).c_str (),
                   human_duration (secs).c_str ());
        }
      int rc = progress ? wait_until_pretty (now, target) : wait_until (target);
      if (rc != 0)
        return rc;
    }

  if (cmd_index < argc)
    {
      std::vector<char *> args;
      for (int j = cmd_index; j < argc; j++)
        args.push_back (argv[j]);
      args.push_back (nullptr);
      execvp (args[0], args.data ());
      fprintf (stderr, "atf: %s: %s\n", args[0], strerror (errno));
      return errno == ENOENT ? 127 : 126;
    }

  return 0;
}
