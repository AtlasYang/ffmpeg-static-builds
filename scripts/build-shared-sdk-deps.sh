#!/usr/bin/env bash
# Build only the permissively licensed dependency required by the shared FFmpeg
# corpus. This prefix is independent from the static CLI dependency prefix.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SHARED_SDK_DEPS_PREFIX="${SHARED_SDK_DEPS_PREFIX:-$BUILD_ROOT/shared-sdk-deps-prefix}"
export SHARED_SDK_DEPS_PREFIX
rm -rf "$SHARED_SDK_DEPS_PREFIX"
mkdir -p "$SHARED_SDK_DEPS_PREFIX/lib" "$SHARED_SDK_DEPS_PREFIX/include"

fetch_source zlib-shared-sdk https://github.com/madler/zlib.git "$ZLIB_VERSION"
cd "$SRC_DIR/zlib-shared-sdk"

if [ "$PLATFORM" = "win" ]; then
    make -f win32/Makefile.gcc clean || true
    make -f win32/Makefile.gcc -j"$JOBS" libz.a
    install -m644 libz.a "$SHARED_SDK_DEPS_PREFIX/lib/libz.a"
    install -m644 zlib.h zconf.h "$SHARED_SDK_DEPS_PREFIX/include/"
else
    make distclean >/dev/null 2>&1 || true
    CFLAGS="${CFLAGS:-} -fPIC" ./configure \
        --prefix="$SHARED_SDK_DEPS_PREFIX" \
        --static
    make -j"$JOBS"
    make install
fi

log "installed shared SDK dependency zlib $ZLIB_VERSION"
