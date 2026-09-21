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

require_build_option() {
    grep -qF -- "$1" <<<"$BUILDCONF" || {
        echo "HWACCEL VIOLATION: configuration is missing $1" >&2
        exit 1
    }
}
case "$PLATFORM" in
    linux)
        for option in --enable-vulkan --disable-vaapi --disable-vdpau \
            --disable-libdrm --disable-v4l2-m2m --disable-libmfx --disable-libvpl; do
            require_build_option "$option"
        done
        ;;
    macos) require_build_option --enable-videotoolbox ;;
    win)
        for option in --enable-d3d11va --enable-d3d12va --enable-dxva2 \
            --enable-mediafoundation; do
            require_build_option "$option"
        done
        ;;
esac

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
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/hwcontext.h>
int main(void) {
    printf("version: %s\n", av_version_info());
    printf("license: %s\n", avutil_license());
    printf("configuration: %s\n", avutil_configuration());
    enum AVHWDeviceType type = AV_HWDEVICE_TYPE_NONE;
    while ((type = av_hwdevice_iterate_types(type)) != AV_HWDEVICE_TYPE_NONE)
        printf("hwdevice: %s\n", av_hwdevice_get_type_name(type));
    const char *encoders[] = {
        "h264_vulkan", "hevc_vulkan", "av1_vulkan",
        "h264_videotoolbox", "hevc_videotoolbox",
        "h264_mf", "hevc_mf", NULL
    };
    for (const char **name = encoders; *name; name++)
        if (avcodec_find_encoder_by_name(*name))
            printf("encoder: %s\n", *name);
    return 0;
}
EOF
cc "$AUDIT_DIR/audit.c" -o "$AUDIT_DIR/audit$EXE" \
    $(pkg-config --cflags --libs libavcodec libswresample libavutil)

case "$PLATFORM" in
    linux) RUNTIME_REPORT="$(LD_LIBRARY_PATH="$SDK_PREFIX/lib" "$AUDIT_DIR/audit$EXE")" ;;
    macos) RUNTIME_REPORT="$(DYLD_LIBRARY_PATH="$SDK_PREFIX/lib" "$AUDIT_DIR/audit$EXE")" ;;
    win) RUNTIME_REPORT="$(PATH="$SDK_PREFIX/bin:$PATH" "$AUDIT_DIR/audit$EXE")" ;;
esac
RUNTIME_VERSION="$(sed -n 's/^version: //p' <<<"$RUNTIME_REPORT")"
if [ "${RUNTIME_VERSION#n}" != "$VERSION" ]; then
    echo "unexpected FFmpeg runtime version" >&2
    printf '%s\n' "$RUNTIME_REPORT" >&2
    exit 1
fi
grep -q '^license: LGPL version 2\.1 or later$' <<<"$RUNTIME_REPORT" || {
    echo "unexpected FFmpeg runtime license" >&2
    printf '%s\n' "$RUNTIME_REPORT" >&2
    exit 1
}

require_runtime_feature() {
    grep -qFx -- "$1" <<<"$RUNTIME_REPORT" || {
        echo "missing shared SDK runtime feature: $1" >&2
        printf '%s\n' "$RUNTIME_REPORT" >&2
        exit 1
    }
}
case "$PLATFORM" in
    linux)
        require_runtime_feature "hwdevice: vulkan"
        UNEXPECTED_HWDEVICES="$(sed -n 's/^hwdevice: //p' <<<"$RUNTIME_REPORT" \
            | grep -vx 'vulkan' || true)"
        [ -z "$UNEXPECTED_HWDEVICES" ] || {
            echo "Linux shared SDK must expose Vulkan only; unexpected devices:" >&2
            printf '%s\n' "$UNEXPECTED_HWDEVICES" >&2
            exit 1
        }
        require_runtime_feature "encoder: h264_vulkan"
        require_runtime_feature "encoder: hevc_vulkan"
        require_runtime_feature "encoder: av1_vulkan"
        ;;
    macos)
        require_runtime_feature "hwdevice: videotoolbox"
        require_runtime_feature "encoder: h264_videotoolbox"
        require_runtime_feature "encoder: hevc_videotoolbox"
        ;;
    win)
        require_runtime_feature "hwdevice: d3d11va"
        require_runtime_feature "hwdevice: d3d12va"
        require_runtime_feature "hwdevice: dxva2"
        require_runtime_feature "encoder: h264_mf"
        require_runtime_feature "encoder: hevc_mf"
        ;;
esac

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
    if [ "$PLATFORM" = "linux" ]; then
        echo "Vulkan-Headers  $VULKAN_HEADERS_VERSION (Apache-2.0 OR MIT; headers only)"
    fi
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
