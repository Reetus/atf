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

"$ATF" -q "+30 seconds" &
pid=$!
sleep 1
kill -INT "$pid" 2>/dev/null
wait "$pid"
check_eq "SIGINT exits 128+2" 130 "$?"

echo "== CLI =="
run_rc "no arguments" 2 "$ATF"
run_rc "unknown option" 2 "$ATF" -z now
run_rc "unparsable time" 2 "$ATF" -p nonsense
run_rc "help" 0 "$ATF" --help
run_rc "version" 0 "$ATF" --version

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
