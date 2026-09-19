#!/bin/sh
# Functional tests for atf.
#
# Usage: tests/run.sh [path-to-atf]
set -u

ATF=${1:-./atf}
case "$ATF" in
    /*) ;;
    *) ATF="$(pwd)/$ATF" ;;
esac

pass=0
fail=0

t_ok() { pass=$((pass + 1)); }
t_fail() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1" >&2; }

check_eq() { # desc expected actual
    if [ "$2" = "$3" ]; then
        t_ok
    else
        t_fail "$1 (expected '$2', got '$3')"
    fi
}

run_rc() { # desc expected-rc command...
    desc=$1
    want=$2
    shift 2
    "$@" >/dev/null 2>&1
    check_eq "$desc" "$want" "$?"
}

expect_time() { # desc input expected-epoch
    desc=$1
    input=$2
    want=$3
    got=$("$ATF" -p "$input" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        t_fail "$desc (exit $rc)"
    else
        check_eq "$desc" "$want" "$got"
    fi
}

echo "== parsing =="
expect_time "ISO 8601 space + offset" "2026-10-26 23:00+07:00" 1793030400
expect_time "ISO 8601 T + Z" "2026-10-26T23:00:00Z" 1793055600
expect_time "epoch" "@1800000000" 1800000000

a=$("$ATF" -p tomorrow 23:00 2>/dev/null)
b=$("$ATF" -p "tomorrow 23:00" 2>/dev/null)
check_eq "multi-token time" "$b" "$a"

now=$("$ATF" -p now)
mid=$("$ATF" -p "00:00")
if [ "$mid" -gt "$now" ] && [ $((mid - now)) -le 93600 ]; then
    t_ok
else
    t_fail "bare time rolls to next day (00:00 -> $mid, now=$now)"
fi

plus1=$("$ATF" -p "+1 hour")
delta=$((plus1 - now))
if [ "$delta" -ge 3595 ] && [ "$delta" -le 3601 ]; then
    t_ok
else
    t_fail "relative +1 hour (delta=${delta}s)"
fi

# Duration shorthand: w/d/h/m/s/ms, combinable, whitespace allowed.
for spec_secs in "90s:90" "2h30m:9000" "1h 15m:4500" "1w:604800" "1m:60" "250ms:0"; do
    spec=${spec_secs%:*}
    want=${spec_secs#*:}
    base=$("$ATF" -p now)
    got=$("$ATF" -p "$spec" 2>/dev/null)
    d=$((got - base))
    if [ "$d" -ge "$want" ] && [ "$d" -le "$((want + 3))" ]; then
        t_ok
    else
        t_fail "duration '$spec' (delta=${d}s, want ~${want})"
    fi
done

# ":MM[:SS]" shorthand: next occurrence within the hour, in TZ.
for spec in ":55" ":55:30"; do
    case "$spec" in
        ":55") want_utc_min=55; want_utc_sec=0 ;;
        *) want_utc_min=55; want_utc_sec=30 ;;
    esac
    want=$((want_utc_min * 60 + want_utc_sec))
    now3=$("$ATF" -p now)
    mark=$(TZ=UTC "$ATF" -p "$spec" 2>/dev/null)
    if [ -n "$mark" ] && [ "$mark" -gt "$((now3 - 1))" ] \
       && [ $((mark - now3)) -le 3601 ] && [ $((mark % 3600)) -eq "$want" ]; then
        t_ok
    else
        t_fail "'$spec' targets next occurrence (mark=$mark now=$now3)"
    fi
done

# TZ offsets with minutes shift the UTC epoch of the mark.
mark=$(TZ=Asia/Kathmandu "$ATF" -p ":55" 2>/dev/null)
if [ -n "$mark" ] && [ $((mark % 3600)) -eq 600 ]; then
    t_ok
else
    t_fail "':55' honors TZ offset (mark=$mark)"
fi

run_rc "minute out of range" 2 "$ATF" -p ":60"
run_rc "junk after shorthand" 2 "$ATF" -p ":5x"

echo "== timezone =="
check_eq "TZ=Asia/Bangkok" 1793030400 \
    "$(TZ=Asia/Bangkok "$ATF" -p "2026-10-26 23:00")"
check_eq "TZ=UTC" 1793055600 \
    "$(TZ=UTC "$ATF" -p "2026-10-26 23:00")"
check_eq "TZ=America/New_York DST" 1793070000 \
    "$(TZ=America/New_York "$ATF" -p "2026-10-26 23:00")"
check_eq "explicit offset beats TZ" 1793055600 \
    "$(TZ=Asia/Bangkok "$ATF" -p "2026-10-26 23:00+00:00")"
check_eq "TZ string in TIME" 1793030400 \
    "$(TZ=UTC "$ATF" -p 'TZ="Asia/Bangkok" 2026-10-26 23:00')"
check_eq "epoch ignores TZ" 1800000000 \
    "$(TZ=Asia/Bangkok "$ATF" -p @1800000000)"

err=$(TZ=Asia/Bangkok "$ATF" "+1 second" -- true 2>&1 >/dev/null)
case "$err" in
    *"+07"*) t_ok ;;
    *) t_fail "status line uses TZ (stderr='$err')" ;;
esac

echo "== past times =="
run_rc "explicit past date is refused" 1 "$ATF" -p "2020-01-01 00:00"
run_rc "force runs past date now" 0 "$ATF" -f -p "2020-01-01 00:00"

# All clock-time forms roll forward instead of erroring, including military
# time (regression: "atf 0200" once failed as a past time).
now2=$("$ATF" -p now)
rolled=$("$ATF" -p 0200 2>/dev/null)
if [ -n "$rolled" ] && [ "$rolled" -ge "$((now2 - 2))" ]; then
    t_ok
else
    t_fail "military time 0200 rolls forward (got '$rolled')"
fi

far=$(TZ=Pacific/Kiritimati "$ATF" -p 0000 2>/dev/null)
if [ -n "$far" ] && [ "$far" -gt "$now2" ] && [ $((far - now2)) -le 90000 ]; then
    t_ok
else
    t_fail "military midnight rolls in UTC+14 (got '$far')"
fi

echo "== execution =="
run_rc "exec true" 0 "$ATF" -q now -- true
run_rc "exec false" 1 "$ATF" -q now -- false
run_rc "exec exit 42" 42 "$ATF" -q now -- sh -c 'exit 42'
run_rc "exec missing command" 127 "$ATF" -q now -- atf-no-such-command-xyz
run_rc "no command exits 0" 0 "$ATF" -q now
run_rc "options terminate at time" 0 "$ATF" -q -- now

out=$("$ATF" -q now -- echo hello)
check_eq "exec output" hello "$out"

echo "== waiting =="
started=$("$ATF" -p now)
"$ATF" "+1 second" -- true 2>/dev/null
rc=$?
finished=$("$ATF" -p now)
elapsed=$((finished - started))
if [ "$rc" -eq 0 ] && [ "$elapsed" -ge 1 ]; then
    t_ok
else
    t_fail "waits ~1s (rc=$rc elapsed=${elapsed}s)"
fi

err=$("$ATF" "+1 second" -- true 2>&1 >/dev/null)
case "$err" in
    *"waiting until"*) t_ok ;;
    *) t_fail "status line (stderr='$err')" ;;
esac

err=$("$ATF" -q "+1 second" -- true 2>&1 >/dev/null)
check_eq "quiet suppresses status" "" "$err"

# --pretty falls back to one line when stderr is not a terminal.
err=$("$ATF" --pretty "+1 second" -- true 2>&1 >/dev/null)
case "$err" in
    *"waiting until"*) t_ok ;;
    *) t_fail "pretty falls back off-terminal (stderr='$err')" ;;
esac

err=$("$ATF" -q --pretty "+1 second" -- true 2>&1 >/dev/null)
check_eq "quiet beats pretty" "" "$err"

if command -v script >/dev/null 2>&1; then
    pty=$(script -qec "$ATF --pretty '+1 second' -- true" /dev/null 2>/dev/null \
          | tr '\r' '\n')
    case "$pty" in
        *"%"*) t_ok ;;
        *) t_fail "pretty draws a progress line on a terminal" ;;
    esac
else
    echo "skip: script(1) unavailable, not testing the pty progress bar"
fi

"$ATF" -q "+30 seconds" &
pid=$!
sleep 1
kill -INT "$pid" 2>/dev/null
wait "$pid"
check_eq "SIGINT exits 128+2" 130 "$?"

echo "== every =="
run_rc "--every needs a command" 2 "$ATF" -e 1m
run_rc "--every rejects a bad interval" 2 "$ATF" -e 1q -- true
run_rc "--every= form accepted" 0 "$ATF" --every=1h -p now

first=$("$ATF" -e 1h -p "23:00" 2>/dev/null)
nowe=$("$ATF" -p now)
if [ -n "$first" ] && [ "$first" -gt "$nowe" ]; then
    t_ok
else
    t_fail "-e -p prints the first target (first=$first now=$nowe)"
fi

# The loop runs repeatedly until interrupted.
tmp=$(mktemp)
"$ATF" -e 500ms -- sh -c 'echo tick' >"$tmp" 2>/dev/null &
pid=$!
sleep 2.2
kill -INT "$pid" 2>/dev/null
wait "$pid"
rc=$?
ticks=$(grep -c tick "$tmp")
rm -f "$tmp"
if [ "$rc" -eq 130 ] && [ "$ticks" -ge 3 ]; then
    t_ok
else
    t_fail "--every repeats and stops on SIGINT (rc=$rc ticks=$ticks)"
fi

# Without TIME the first run is immediate.
tmp=$(mktemp)
"$ATF" -e 1h -- echo boot >"$tmp" 2>/dev/null &
pid=$!
sleep 0.3
if grep -q boot "$tmp"; then t_ok; else t_fail "--every without TIME starts now"; fi
kill -INT "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
rm -f "$tmp"

# A first target in the past must not spin catching up through missed slots.
tmp=$(mktemp)
started=$("$ATF" -p now)
"$ATF" -e 1h "2020-01-01" -- echo stale >"$tmp" 2>/dev/null &
pid=$!
sleep 0.5
finished=$("$ATF" -p now)
if grep -q stale "$tmp" && [ $((finished - started)) -le 3 ]; then
    t_ok
else
    t_fail "--every with past TIME starts immediately (elapsed=$((finished - started))s)"
fi
kill -INT "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
rm -f "$tmp"

echo "== install =="
root=$(CDPATH= cd -- "$(dirname -- "$ATF")" && pwd)
dest=$(mktemp -d)
if make -s -C "$root" install DESTDIR="$dest" PREFIX=/usr/local >/dev/null 2>&1; then
    for f in usr/local/bin/atf \
             usr/local/share/man/man1/atf.1 \
             usr/local/share/bash-completion/completions/atf \
             usr/local/share/zsh/site-functions/_atf; do
        if [ -f "$dest/$f" ]; then t_ok; else t_fail "install missing $f"; fi
    done
else
    t_fail "make install failed"
fi
rm -rf "$dest"

if command -v bash >/dev/null 2>&1; then
    if bash -n "$root/completions/atf.bash"; then
        t_ok
    else
        t_fail "bash completion syntax"
    fi
fi

echo "== CLI =="
run_rc "no arguments" 2 "$ATF"
run_rc "unknown option" 2 "$ATF" -z now
run_rc "unparsable time" 2 "$ATF" -p nonsense
run_rc "help" 0 "$ATF" --help
run_rc "version" 0 "$ATF" --version

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
