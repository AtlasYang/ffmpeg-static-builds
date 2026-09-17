#!/usr/bin/env bash
# Package the shared SDK as a relocatable development/runtime archive.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SDK_PREFIX="${SDK_PREFIX:-$BUILD_ROOT/shared-sdk-prefix}"
FFMPEG_SOURCE_DIR="${FFMPEG_SOURCE_DIR:-$SRC_DIR/ffmpeg-shared-sdk}"
ZLIB_SOURCE_DIR="$SRC_DIR/zlib-shared-sdk"
LIBRARIES=(avcodec avdevice avfilter avformat avutil swresample swscale)
PACKAGE_ROOT="$BUILD_ROOT/shared-sdk-package"
STAGE="$PACKAGE_ROOT/$ASSET_BASE"

rm -rf "$PACKAGE_ROOT"
mkdir -p "$STAGE/bin" "$STAGE/lib/pkgconfig" "$STAGE/include" \
    "$STAGE/licenses/FFmpeg" "$STAGE/licenses/zlib"

for library in "${LIBRARIES[@]}"; do
    cp -R "$SDK_PREFIX/include/lib$library" "$STAGE/include/"
    cp "$SDK_PREFIX/lib/pkgconfig/lib$library.pc" "$STAGE/lib/pkgconfig/"
    case "$PLATFORM" in
        linux)
            cp -a "$SDK_PREFIX/lib/lib$library.so"* "$STAGE/lib/"
            ;;
        macos)
            find "$SDK_PREFIX/lib" -maxdepth 1 \( -type f -o -type l \) \
                -name "lib$library*.dylib" -exec cp -a {} "$STAGE/lib/" \;
            ;;
        win)
            cp "$SDK_PREFIX"/bin/"$library"-*.dll "$STAGE/bin/"
            cp "$SDK_PREFIX/lib/lib$library.dll.a" "$STAGE/lib/"
            ;;
    esac
done

# FFmpeg .pc files normally contain the absolute build prefix. Make them
# relocatable inside the extracted archive instead.
for pc_file in "$STAGE"/lib/pkgconfig/*.pc; do
    sed -i.bak \
        -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
        -e 's|^libdir=.*|libdir=${prefix}/lib|' \
        -e 's|^includedir=.*|includedir=${prefix}/include|' \
        "$pc_file"
    rm -f "$pc_file.bak"
    if grep -qF "$SDK_PREFIX" "$pc_file"; then
        echo "non-relocatable build path remains in $pc_file" >&2
        exit 1
    fi
done

for notice in COPYING.LGPLv2.1 COPYING.LGPLv3 LICENSE.md CREDITS; do
    cp "$FFMPEG_SOURCE_DIR/$notice" "$STAGE/licenses/FFmpeg/"
done
cp "$ZLIB_SOURCE_DIR/LICENSE" "$STAGE/licenses/zlib/"

cat > "$STAGE/README.txt" <<EOF
FFmpeg shared SDK $VERSION ($PLATFORM-$ARCH)

This archive is built from FFmpeg $FFMPEG_TAG and licensed under
LGPL-2.1-or-later. It contains shared libraries, headers, pkg-config metadata
and (on Windows) import libraries for rsmpeg/rusty_ffmpeg.

Set PKG_CONFIG_PATH to <archive>/lib/pkgconfig on Linux/macOS. Put
<archive>/lib (Linux/macOS) or <archive>/bin (Windows) on the runtime loader
search path, or install those shared libraries using the platform's normal
application packaging mechanism.

When building rusty_ffmpeg/rsmpeg against this SDK, also set
FFMPEG_LINK_MODE=dynamic and FFMPEG_PKG_CONFIG_PATH=<archive>/lib/pkgconfig.

The libraries are replaceable with ABI-compatible FFmpeg 8 builds. License
notices are under licenses/FFmpeg and licenses/zlib. Full build configuration
is published beside this archive as $ASSET_BASE.configure.txt.
EOF

# Prove that the rewritten pkg-config files work from their staged, relocated
# path and link against the shared libraries rather than the build prefix.
RELOCATE_AUDIT="$PACKAGE_ROOT/relocate-audit.c"
cat > "$RELOCATE_AUDIT" <<'EOF'
#include <libavutil/avutil.h>
int main(void) { return avutil_version() == 0; }
EOF
PKG_CONFIG_PATH="$STAGE/lib/pkgconfig" cc "$RELOCATE_AUDIT" \
    -o "$PACKAGE_ROOT/relocate-audit$EXE" \
    $(PKG_CONFIG_PATH="$STAGE/lib/pkgconfig" pkg-config --cflags --libs libavutil)
case "$PLATFORM" in
    linux) LD_LIBRARY_PATH="$STAGE/lib" "$PACKAGE_ROOT/relocate-audit$EXE" ;;
    macos) DYLD_LIBRARY_PATH="$STAGE/lib" "$PACKAGE_ROOT/relocate-audit$EXE" ;;
    win) PATH="$STAGE/bin:$PATH" "$PACKAGE_ROOT/relocate-audit$EXE" ;;
esac

mkdir -p "$DIST_DIR"
cd "$PACKAGE_ROOT"
if [ "$PLATFORM" = "win" ]; then
    ARCHIVE="$DIST_DIR/$ASSET_BASE.zip"
    rm -f "$ARCHIVE"
    zip -9 -r "$ARCHIVE" "$ASSET_BASE"
    unzip -l "$ARCHIVE"
else
    ARCHIVE="$DIST_DIR/$ASSET_BASE.tar.gz"
    rm -f "$ARCHIVE"
    tar -czf "$ARCHIVE" "$ASSET_BASE"
    tar -tzf "$ARCHIVE"
fi

log "packaged $ARCHIVE"
