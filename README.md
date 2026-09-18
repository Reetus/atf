# atf — run a command at a specified time, in the foreground

`atf` waits until a loosely specified time, then runs a command and exits
with its status. With no command it just exits, so it can be dropped into a
sequence of shell commands like an `sleep` that takes a date instead of a
duration.

```sh
atf 23:00 -- make backup            # run at 23:00 today/tomorrow
atf '2026-10-26 23:00+07:00' -- systemctl restart app
atf tomorrow 06:30 -- ./deploy.sh
atf +2 hours                        # just wait (like sleep 7200)
atf 23:00 && echo backup started    # chain on its exit status
```

`at` runs jobs in the background via a daemon; `sleep` only takes a
duration. `atf` stays in the foreground and takes the same loose grammar as
GNU `date -d` and `at`, so it works in scripts, cron wrappers, and chained
commands.

## Time grammar

Handled by gnulib's `parse-datetime` (the parser used by GNU `at` and
`date`):

| Input | Meaning |
| --- | --- |
| `23:00`, `4pm`, `0200`, `noon`, `midnight` | clock time |
| `2026-10-26 23:00+07:00`, `2026-10-26T23:00:00Z` | ISO 8601 with offset |
| `tomorrow 23:00`, `next monday`, `2 days ago` | relative words |
| `+2 hours`, `+90 minutes` | relative to now |
| `@1800000000` | seconds since the epoch |
| `now` | run immediately |

A bare clock time that has already passed means the next day (like `at`).
An explicitly dated time in the past is an error unless `-f` is given.

Times without an explicit offset use the `TZ` environment variable, and an
explicit offset always wins over `TZ`:

```sh
TZ=Asia/Bangkok atf 23:00 -- cmd     # 23:00 Bangkok time
atf '2026-10-26 23:00+00:00' -- cmd  # 23:00 UTC regardless of TZ
atf 'TZ="Asia/Bangkok" 23:00' -- cmd # zone inside the time string
```

The status line and the tomorrow-rollover logic use the same zone.

## Usage

```
atf [OPTION]... TIME [-- COMMAND [ARG]...]

  -q, --quiet       do not print the status line
  -p, --print       print the target Unix time and exit
  -f, --force       if TIME is in the past, run immediately
  -h, --help        display help and exit
  -v, --version     output version information and exit
```

Options must come before `TIME`; everything between `TIME` and `--` is
joined with spaces, so multi-word times work without quoting if you prefer:
`atf tomorrow 23:00 -- cmd`. `COMMAND` is executed directly with `execvp`,
not through a shell; use `-- sh -c '...'` when shell syntax is needed.

Exit status: the command's status, `127` if it cannot be found, `126` if it
cannot be executed, `2` for usage/parse errors, `1` for a past time that was
refused, `128+N` when interrupted by signal `N`, or `0` when there is no
command. `--print` always exits `0` (or `1`/`2` as above) without waiting.

The wait uses `clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME)`, so NTP clock
steps and suspend/resume are handled by the kernel: `atf` wakes at the
requested wall-clock time.

## Building

Only `make` and a C/C++ compiler are needed (`apt install build-essential`).

```sh
make            # dynamic ./atf
make static     # fully static ./atf: no runtime dependencies
make test       # functional test suite
make install    # PREFIX=/usr/local by default
```

The static binary is self-contained (no libc, libstdc++, or GNU `date`
dependency at runtime) and can be copied between Ubuntu machines or between
distro versions. Build on each architecture you need (`x86_64`, `arm64`, …).

## Layout

```
src/atf.cpp                   the tool
third_party/parse-datetime/   vendored gnulib parse-datetime (GNU coreutils 9.4)
third_party/compat/           shims: time_rz, nstrftime, gettext, stdckdint
tools/vendor-parse-datetime.sh  re-vendor or bump the parser version
tests/run.sh                  functional tests
```

Run `tools/vendor-parse-datetime.sh` to re-extract the vendored parser from a
coreutils release tarball (cached in `.cache/`); it also regenerates the
glibc `config.h`. See `third_party/parse-datetime/README` for provenance.

## License

GPL-3.0-or-later. The vendored parser is distributed by the GNU project
under GPL-3.0-or-later (the Bison-generated `parse-datetime.c` carries
Bison's special exception).
