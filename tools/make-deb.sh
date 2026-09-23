#!/bin/sh
# Build a .deb for the already-built ./atf using only dpkg-deb.
#
# The package is architecture-dependent but has no runtime dependencies:
# ./atf is statically linked, so the same .deb works on Debian and Ubuntu
# releases of the same architecture. Run `make deb` (which builds a static
# binary first) rather than calling this directly.
#
# Environment:
#   VERSION          package version (default: Makefile VERSION)
#   ARCH             package architecture (default: dpkg --print-architecture)
#   DEB_MAINTAINER   "Name <email>" (default: git config user.name/email)
#
# Prints the path of the built .deb on stdout.
set -eu
umask 022

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:-$(sed -n 's/^VERSION := //p' "$ROOT/Makefile" | head -1)}
VERSION=${VERSION:-0.1.0}
ARCH=${ARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}

if [ ! -x "$ROOT/atf" ]; then
    echo "make-deb: $ROOT/atf not found; run 'make static' first" >&2
    exit 1
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "make-deb: dpkg-deb not found (install dpkg)" >&2
    exit 1
fi
if ! command -v gzip >/dev/null 2>&1; then
    echo "make-deb: gzip not found" >&2
    exit 1
fi

name=$(git -C "$ROOT" config user.name 2>/dev/null || true)
email=$(git -C "$ROOT" config user.email 2>/dev/null || true)
MAINTAINER=${DEB_MAINTAINER:-${name:-atf packager} <${email:-nobody@example.com}>}

STAGE="$ROOT/build/deb/atf_${VERSION}_${ARCH}"
DIST="$ROOT/dist"
DEB="$DIST/atf_${VERSION}_${ARCH}.deb"

rm -rf "$STAGE"
install -Dm755 "$ROOT/atf" "$STAGE/usr/bin/atf"
install -Dm644 "$ROOT/atf.1" "$STAGE/usr/share/man/man1/atf.1"
gzip -9n "$STAGE/usr/share/man/man1/atf.1"
install -Dm644 "$ROOT/completions/atf.bash" \
    "$STAGE/usr/share/bash-completion/completions/atf"
install -Dm644 "$ROOT/completions/_atf" \
    "$STAGE/usr/share/zsh/vendor-completions/_atf"

DOC="$STAGE/usr/share/doc/atf"
install -Dm644 "$ROOT/README.md" "$DOC/README.md"
cat > "$DOC/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: atf

Files: *
Copyright: 2026 $name
License: GPL-3.0-or-later
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 .
 On Debian systems the full text of the GPL version 3 can be found in
 /usr/share/common-licenses/GPL-3.
EOF
cat > "$DOC/changelog" <<EOF
atf ($VERSION) unstable; urgency=medium

  * Local package built with tools/make-deb.sh.

 -- $MAINTAINER  $(date -R)
EOF
gzip -9n "$DOC/changelog"

mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: atf
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $(du -sk "$STAGE" | cut -f1)
Section: utils
Priority: optional
Description: run a command at a loosely specified time, in the foreground
 atf waits until a time given in the GNU date/at grammar (ISO 8601,
 explicit UTC offsets, relative words, durations, @epoch) and then runs
 a command, or exits like sleep when none is given. Times without an
 offset use the TZ environment; a clock time already past rolls over to
 tomorrow.
 .
 The binary is statically linked, so this package has no runtime
 dependencies and works on Debian and Ubuntu releases of the same
 architecture.
EOF

mkdir -p "$DIST"
if dpkg-deb --help 2>&1 | grep -q -- '--root-owner-group'; then
    dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB" >&2
else
    if ! command -v fakeroot >/dev/null 2>&1; then
        echo "make-deb: need dpkg-deb >= 1.19 or fakeroot for root ownership" >&2
        exit 1
    fi
    fakeroot dpkg-deb -Zxz --build "$STAGE" "$DEB" >&2
fi

echo "$DEB"
