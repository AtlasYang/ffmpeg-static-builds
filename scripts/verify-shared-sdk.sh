#!/usr/bin/env bash
# Validate the shared SDK, enforce its license/build policy and emit an
# auditable configure/runtime report beside the release archive.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SDK_PREFIX="${SDK_PREFIX:-$BUILD_ROOT/shared-sdk-prefix}"
FFMPEG_SOURCE_DIR="${FFMPEG_SOURCE_DIR:-$SRC_DIR/ffmpeg-shared-sdk}"
REPORT="$DIST_DIR/$ASSET_BASE.configure.txt"
LIBRARIES=(avcodec avdevice avfilter avformat avutil swresample swscale)

[ -f "$FFMPEG_SOURCE_DIR/ffbuild/config.mak" ] || {
    echo "missing FFmpeg configuration under $FFMPEG_SOURCE_DIR" >&2
    exit 1
}

BUILDCONF="$(sed -n 's/^FFMPEG_CONFIGURATION=//p' "$FFMPEG_SOURCE_DIR/ffbuild/config.mak")"
[ -n "$BUILDCONF" ] || { echo "could not read FFmpeg configuration" >&2; exit 1; }

FORBIDDEN=(
    --enable-gpl
    --enable-nonfree
    --enable-version3
    --enable-static
    --enable-libx264
    --enable-libx265
    --enable-libxvid
    --enable-libfdk-aac
    --enable-libsmbclient
    --enable-libvmaf
    --enable-mbedtls
)
REQUIRED=(
    --disable-gpl
    --disable-nonfree
    --disable-version3
    --disable-autodetect
    --disable-programs
    --disable-static
    --enable-shared
)

violations=0
for option in "${FORBIDDEN[@]}"; do
    if grep -qF -- "$option" <<<"$BUILDCONF"; then
        echo "LICENSE/ABI VIOLATION: configuration contains $option" >&2
        violations=$((violations + 1))
    fi
done
for option in "${REQUIRED[@]}"; do
    if ! grep -qF -- "$option" <<<"$BUILDCONF"; then
        echo "LICENSE/ABI VIOLATION: configuration is missing $option" >&2
        violations=$((violations + 1))
    fi
done
[ "$violations" -eq 0 ] || { echo "refusing to publish this SDK" >&2; exit 1; }

for library in "${LIBRARIES[@]}"; do
    [ -d "$SDK_PREFIX/include/lib$library" ] || {
        echo "missing headers for lib$library" >&2
        exit 1
    }
    [ -f "$SDK_PREFIX/lib/pkgconfig/lib$library.pc" ] || {
        echo "missing pkg-config metadata for lib$library" >&2
        exit 1
    }
    case "$PLATFORM" in
        linux) compgen -G "$SDK_PREFIX/lib/lib$library.so*" >/dev/null ;;
        macos) compgen -G "$SDK_PREFIX/lib/lib$library*.dylib" >/dev/null ;;
        win)
            compgen -G "$SDK_PREFIX/bin/$library-*.dll" >/dev/null
            [ -f "$SDK_PREFIX/lib/lib$library.dll.a" ]
            ;;
    esac || { echo "missing shared library for $library" >&2; exit 1; }
done

export PKG_CONFIG_PATH="$SDK_PREFIX/lib/pkgconfig"
AUDIT_DIR="$BUILD_ROOT/shared-sdk-audit"
rm -rf "$AUDIT_DIR"
mkdir -p "$AUDIT_DIR"
cat > "$AUDIT_DIR/audit.c" <<'EOF'
#include <stdio.h>
#include <libavutil/avutil.h>
int main(void) {
    printf("version: %s\n", av_version_info());
    printf("license: %s\n", avutil_license());
    printf("configuration: %s\n", avutil_configuration());
    return 0;
}
EOF
cc "$AUDIT_DIR/audit.c" -o "$AUDIT_DIR/audit$EXE" \
    $(pkg-config --cflags --libs libavutil)

case "$PLATFORM" in
    linux) RUNTIME_REPORT="$(LD_LIBRARY_PATH="$SDK_PREFIX/lib" "$AUDIT_DIR/audit$EXE")" ;;
    macos) RUNTIME_REPORT="$(DYLD_LIBRARY_PATH="$SDK_PREFIX/lib" "$AUDIT_DIR/audit$EXE")" ;;
    win) RUNTIME_REPORT="$(PATH="$SDK_PREFIX/bin:$PATH" "$AUDIT_DIR/audit$EXE")" ;;
esac
grep -q '^version: n\?8\.0\.3$' <<<"$RUNTIME_REPORT" || {
    echo "unexpected FFmpeg runtime version" >&2
    printf '%s\n' "$RUNTIME_REPORT" >&2
    exit 1
}
grep -q '^license: LGPL version 2\.1 or later$' <<<"$RUNTIME_REPORT" || {
    echo "unexpected FFmpeg runtime license" >&2
    printf '%s\n' "$RUNTIME_REPORT" >&2
    exit 1
}

{
    echo "FFmpeg shared SDK build report"
    echo "====================================="
    echo
    echo "FFmpeg version : $FFMPEG_TAG"
    echo "Target         : $PLATFORM-$ARCH"
    echo "Host runner    : $(uname -srm)"
    echo "Build sysroot  : $( [ -r /etc/os-release ] && . /etc/os-release && echo "$PRETTY_NAME" || sw_vers -productVersion 2>/dev/null || echo "$(uname -s)" )"
    echo "Built at (UTC) : $(date -u '+%Y-%m-%d %H:%M:%S')"
    echo "License        : LGPL-2.1-or-later"
    echo
    echo "Pinned dependency"
    echo "-----------------"
    echo "zlib            $ZLIB_VERSION (zlib license; statically included)"
    echo
    echo "Runtime identity"
    echo "----------------"
    printf '%s\n' "$RUNTIME_REPORT"
    echo
    echo "configure options"
    echo "-----------------"
    printf '%s\n' "$BUILDCONF"
    echo
    echo "pkg-config versions"
    echo "-------------------"
    for library in "${LIBRARIES[@]}"; do
        printf '%-14s %s\n' "lib$library" "$(pkg-config --modversion "lib$library")"
    done
    echo
    echo "dynamic library dependencies"
    echo "----------------------------"
    for library in "${LIBRARIES[@]}"; do
        case "$PLATFORM" in
            linux) file="$(find "$SDK_PREFIX/lib" -maxdepth 1 -type f -name "lib$library.so.*" | sort | head -1)" ;;
            macos) file="$(find "$SDK_PREFIX/lib" -maxdepth 1 -type f -name "lib$library*.dylib" | sort | head -1)" ;;
            win) file="$(find "$SDK_PREFIX/bin" -maxdepth 1 -type f -name "$library-*.dll" | sort | head -1)" ;;
        esac
        echo "\$ $(basename "$file")"
        case "$PLATFORM" in
            linux) LD_LIBRARY_PATH="$SDK_PREFIX/lib" ldd "$file" 2>&1 || true ;;
            macos) DYLD_LIBRARY_PATH="$SDK_PREFIX/lib" otool -L "$file" 2>&1 || true ;;
            win) objdump -p "$file" | grep -i 'DLL Name' || true ;;
        esac
        echo
    done
} > "$REPORT"

log "shared SDK verification passed, report written to $REPORT"
cat "$REPORT"
