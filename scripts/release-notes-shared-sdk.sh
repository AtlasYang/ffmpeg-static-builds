#!/usr/bin/env bash
# Render the release body for the independent shared-SDK release line.
set -euo pipefail

VERSION="${1:?usage: release-notes-shared-sdk.sh <version> <release-tag> <asset-dir>}"
RELEASE_TAG="${2:?}"
ASSET_DIR="${3:?}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
DL_BASE="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"

TARGETS=(
    "win-x64|Windows|x86_64|zip|Windows 10 or newer"
    "linux-x64|Linux|x86_64|tar.gz|glibc 2.35 or newer (Ubuntu 22.04+, Debian 12+, RHEL 9+)"
    "linux-arm64|Linux|arm64 (aarch64)|tar.gz|glibc 2.35 or newer (Ubuntu 22.04+, Debian 12+, RHEL 9+)"
    "macos-arm64|macOS|arm64 (Apple Silicon)|tar.gz|macOS 11 Big Sur or newer"
    "macos-x64|macOS|x86_64 (Intel)|tar.gz|macOS 10.15 Catalina or newer"
)

human_size() { numfmt --to=iec-i --suffix=B --format='%.1f' < <(stat -c %s "$1"); }

{
    echo "# FFmpeg ${VERSION} shared SDK"
    echo
    echo "LGPL-2.1-or-later shared FFmpeg 8 SDK for dynamic-link consumers."
    echo "This release is independent from the repository's static CLI release line."
    echo
    echo "Each archive includes the seven libraries expected by rusty_ffmpeg"
    echo "(avcodec, avdevice, avfilter, avformat, avutil, swresample and swscale),"
    echo "their headers, relocatable pkg-config metadata, import libraries where"
    echo "applicable, and FFmpeg license notices."
    echo "Pinned zlib ${ZLIB_VERSION:-v1.3.1} is statically included for PNG decoding;"
    echo "its license is included in every archive."
    echo
    echo "Built with \`--disable-gpl --disable-nonfree --disable-version3\`,"
    echo "\`--disable-static --enable-shared --disable-programs\`."
    echo
    echo "## Downloads"
    echo
    echo "| Platform | Architecture | SDK | Size | Build report |"
    echo "|:--|:--|:--|--:|:--|"
    for entry in "${TARGETS[@]}"; do
        IFS='|' read -r target os arch ext _min <<<"$entry"
        archive="ffmpeg-${VERSION}-shared-${target}.${ext}"
        report="ffmpeg-${VERSION}-shared-${target}.configure.txt"
        [ -f "$ASSET_DIR/$archive" ] || { echo "missing asset: $archive" >&2; exit 1; }
        [ -f "$ASSET_DIR/$report" ] || { echo "missing asset: $report" >&2; exit 1; }
        printf '| %s | %s | [%s](%s/%s) | %s | [configure/runtime audit](%s/%s) |\n' \
            "$os" "$arch" "$archive" "$DL_BASE" "$archive" \
            "$(human_size "$ASSET_DIR/$archive")" "$DL_BASE" "$report"
    done
    echo
    echo "## Verification and source"
    echo
    echo "Checksums are in [checksums.sha256](${DL_BASE}/checksums.sha256)."
    echo "The exact upstream source and signature are included as release assets:"
    echo "[ffmpeg-${VERSION}.tar.xz](${DL_BASE}/ffmpeg-${VERSION}.tar.xz) and"
    echo "[ffmpeg-${VERSION}.tar.xz.asc](${DL_BASE}/ffmpeg-${VERSION}.tar.xz.asc)."
    echo "The workflow verifies that signature against the pinned official FFmpeg"
    echo "release-key fingerprint; [the key](${DL_BASE}/ffmpeg-devel.asc) is included."
    echo
    echo "Every configure report records the runtime-reported version, license and"
    echo "configuration plus the dynamic dependencies of each shared library."
    echo
    echo "Built by [\`build-shared-sdk.yml\`](https://github.com/${REPO}/blob/main/.github/workflows/build-shared-sdk.yml)."
}
