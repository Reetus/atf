#!/bin/sh
# Vendor gnulib's parse-datetime parser (as shipped in a coreutils release)
# into third_party/parse-datetime, and generate a config.h for glibc systems.
#
# Usage:
#   tools/vendor-parse-datetime.sh                 # uses coreutils 9.4
#   COREFUTILS_VERSION=9.5 tools/vendor-parse-datetime.sh
#   COREFUTILS_TARBALL=/path/to/coreutils-9.4.tar.xz tools/vendor-parse-datetime.sh
#
# The script is idempotent: only files under third_party/parse-datetime are
# replaced. Hand-written shims live in third_party/compat and are untouched.
set -eu

VERSION="${COREFUTILS_VERSION:-9.4}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEST="$ROOT/third_party/parse-datetime"
CACHE_DIR="$ROOT/.cache"
TARBALL="${COREFUTILS_TARBALL:-$CACHE_DIR/coreutils-$VERSION.tar.xz}"
URL="${COREFUTILS_URL:-https://ftp.gnu.org/gnu/coreutils/coreutils-$VERSION.tar.xz}"

FILES="
parse-datetime.c
parse-datetime.h
parse-datetime.y
parse-datetime-gen.h
c-ctype.c
c-ctype.h
idx.h
intprops.h
intprops-internal.h
timespec.h
gettime.c
arg-nonnull.h
verify.h
config.hin
"

# glibc capabilities that the vendored code should use directly. Anything left
# as "#undef" in config.hin evaluates to 0 in the preprocessor, which selects
# gnulib's fallback paths (and may require more files), so be explicit.
DEFINES="
HAVE_STDBOOL_H
HAVE_COMPOUND_LITERALS
HAVE_CLOCK_GETTIME
HAVE_TIMESPEC_GET
HAVE_DECL_TZNAME
HAVE_TZNAME
HAVE_TM_GMTOFF
HAVE_STRUCT_TM_TM_ZONE
HAVE_UNISTD_H
HAVE_GETTIMEOFDAY
HAVE_LOCALTIME_R
HAVE_GMTIME_R
HAVE_INTTYPES_H
HAVE_STDINT_H
HAVE_STDLIB_H
HAVE_STRING_H
HAVE_SYS_TIME_H
HAVE_SYS_TYPES_H
HAVE_MKTIME
HAVE_TIMEGM
HAVE_DECL_STRFTIME
HAVE_STRFTIME
HAVE_STRFTIME_L
"

if [ ! -f "$TARBALL" ]; then
    mkdir -p "$CACHE_DIR"
    echo "vendor: downloading $URL" >&2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$TARBALL.tmp" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$TARBALL.tmp" "$URL"
    else
        echo "vendor: need curl or wget to download $URL" >&2
        exit 1
    fi
    mv "$TARBALL.tmp" "$TARBALL"
fi

SHA256="$(sha256sum "$TARBALL" | cut -d' ' -f1)"

rm -rf "$DEST"
mkdir -p "$DEST"

for f in $FILES; do
    if ! tar -xJf "$TARBALL" -C "$DEST" --strip-components=2 \
            "coreutils-$VERSION/lib/$f"; then
        echo "vendor: coreutils-$VERSION/lib/$f not found in tarball" >&2
        exit 1
    fi
done

# config.hin from the release tarball is a valid config.h once the platform
# HAVE_* macros are set: it already carries the gnulib _GL_* macro definitions.
cp "$DEST/config.hin" "$DEST/config.h"
for m in $DEFINES; do
    sed -i "s/^#undef $m\$/#define $m 1/" "$DEST/config.h"
done

cat >> "$DEST/config.h" <<'EOF'

/* atf: time_rz is provided by third_party/compat/compat.c, not by gnulib. */
#include <time.h>
typedef struct tm_zone *timezone_t;
#ifdef __cplusplus
extern "C" {
#endif
struct tm *localtime_rz (timezone_t, time_t const *, struct tm *);
time_t mktime_z (timezone_t, struct tm *);
timezone_t tzalloc (char const *);
void tzfree (timezone_t);
#ifdef __cplusplus
}
#endif
EOF

cat > "$DEST/README" <<EOF
Vendored from GNU coreutils $VERSION, lib/* (gnulib parse-datetime module).
Source: $URL
SHA256: $SHA256

Files are extracted verbatim by tools/vendor-parse-datetime.sh, except:
  config.h    generated from config.hin, with a short list of platform
              HAVE_* macros set to 1 and the time_rz declarations appended
  config.hin  verbatim copy, kept for provenance/regeneration

Not vendored (replaced by small shims in third_party/compat):
  time_rz.c   -> timezone_t/tzalloc/mktime_z/localtime_rz using the
                 process TZ environment
  nstrftime   -> system strftime (debug output only; parse_datetime2 flags
                 are not exposed by atf)
  gettext     -> identity macros

parse-datetime.y is GPL-3.0-or-later as distributed by the GNU project
(gnulib module metadata lists LGPL-2.1-or-later; atf follows the stricter
file headers). parse-datetime.c is the Bison-generated parser shipped in the
coreutils release tarball; it is distributed with Bison's special exception.
EOF

echo "vendor: parse-datetime from coreutils $VERSION -> ${DEST#$ROOT/}" >&2
