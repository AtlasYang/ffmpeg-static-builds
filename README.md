# FFmpeg release builds

This repository has two independent LGPL-only release lines for Windows, Linux
and macOS:

- statically linked `ffmpeg` and `ffprobe` command line executables;
- an FFmpeg 8.0.3 shared SDK for dynamic-link consumers such as rsmpeg.

They use separate workflows, scripts, asset names and release tags. The shared SDK
pipeline does not change the existing static CLI artifacts. Keeping both here
records build inputs, configure options and license evidence in one auditable
place without coupling either build to its consuming application.

---

## License policy

**The produced binaries are licensed under LGPL-2.1-or-later. They contain no
GPL and no nonfree components.**

Every build runs `configure` with these four options, and a post-build gate
(`scripts/verify-license.sh`) reads them back out of the compiled binary and
**fails the build** if any of them is missing or contradicted:

| Option                 | Effect                                                                                                                                                                                                                                            |
| :--------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--disable-gpl`        | No GPL-only components. x264, x265, Xvid, and all GPL-licensed filters are unreachable.                                                                                                                                                           |
| `--disable-nonfree`    | No nonfree components, e.g. FDK-AAC.                                                                                                                                                                                                              |
| `--disable-version3`   | Nothing that would upgrade the result to (L)GPL **v3**. Libraries such as libvmaf or mbedTLS would trigger this, so they are excluded.                                                                                                            |
| `--disable-autodetect` | `configure` may not pick up anything that happens to be installed on the CI runner. Every external library has to be named explicitly, which keeps the feature set identical across all five targets and keeps the audit result stable over time. |

The gate additionally rejects the binary if `--enable-gpl`, `--enable-nonfree`,
`--enable-version3`, `--enable-libx264`, `--enable-libx265`, `--enable-libxvid`,
`--enable-libfdk-aac`, `--enable-libvmaf` or `--enable-mbedtls` appears in the
build configuration. The policy is an executed check, not a comment.

Note that many pre-built FFmpeg distributions labelled "LGPL" - including the
`lgpl` variant of [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) -
are built with `--enable-version3` and are therefore **LGPL v3**. The builds here
are deliberately kept at LGPL-2.1-or-later.

### What this means for encoding

H.264 and HEVC encoding are **not available**, because the encoders for them
(x264, x265) are GPL and libfdk-aac is nonfree. Decoding H.264/HEVC works
through FFmpeg's own LGPL decoders. Available video encoders are VP8, VP9
(libvpx), AV1 (libaom) and the native LGPL encoders that ship with FFmpeg.

---

## Included third-party libraries

All dependencies are built from source at pinned versions
(see [`scripts/versions.sh`](scripts/versions.sh)); nothing is taken from the CI
runner image.

| Library                                           | Version | License                               | Purpose         |
| :------------------------------------------------ | :------ | :------------------------------------ | :-------------- |
| [zlib](https://github.com/madler/zlib)            | v1.3.1  | zlib license                          | Deflate streams |
| [libogg](https://github.com/xiph/ogg)             | v1.3.6  | BSD-3-Clause                          | Ogg container   |
| [libvorbis](https://github.com/xiph/vorbis)       | v1.3.7  | BSD-3-Clause                          | Vorbis audio    |
| [libopus](https://github.com/xiph/opus)           | v1.6.1  | BSD-3-Clause                          | Opus audio      |
| [libvpx](https://github.com/webmproject/libvpx)   | v1.17.0 | BSD-3-Clause                          | VP8 / VP9 video |
| [dav1d](https://code.videolan.org/videolan/dav1d) | 1.5.4   | BSD-2-Clause                          | AV1 decoding    |
| [libaom](https://aomedia.googlesource.com/aom)    | v3.15.0 | BSD-2-Clause + AOM Patent License 1.0 | AV1 encoding    |
| [libwebp](https://github.com/webmproject/libwebp) | v1.6.0  | BSD-3-Clause                          | WebP images     |

FFmpeg itself is LGPL-2.1-or-later under this configuration.

Codec **patent** licensing is a separate matter from copyright licensing and is
not covered by the LGPL. AV1 is distributed under the Alliance for Open Media
Patent License 1.0; no patent-encumbered encoders such as H.264, HEVC or AAC-LC
(FDK) are included in these builds.

### Deliberately excluded

- GPL encoders: x264, x265, Xvid
- Nonfree: libfdk-aac
- `--enable-version3` libraries: libvmaf, mbedTLS, libopencore-amr, libvo-amrwbenc
- TLS backends (gnutls / OpenSSL / SChannel / SecureTransport). A consequence of
  `--disable-autodetect`: **`https://` inputs are not supported.** Local files,
  pipes and plain `http://` work.
- iconv, so `-sub_charenc` subtitle charset conversion is unavailable.
- VideoToolbox and every other hardware acceleration backend, keeping the five
  targets feature-identical.

---

## Downloads

Latest release: **[Releases page](https://github.com/AtlasYang/ffmpeg-static-builds/releases/latest)**

| Platform | Architecture          | Asset                                 | Minimum OS                                      |
| :------- | :-------------------- | :------------------------------------ | :---------------------------------------------- |
| Windows  | x86_64                | `ffmpeg-<version>-win-x64.zip`        | Windows 10                                      |
| Linux    | x86_64                | `ffmpeg-<version>-linux-x64.tar.gz`   | glibc 2.35 (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| Linux    | arm64                 | `ffmpeg-<version>-linux-arm64.tar.gz` | glibc 2.35 (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| macOS    | arm64 (Apple Silicon) | `ffmpeg-<version>-macos-arm64.tar.gz` | macOS 11 Big Sur                                |
| macOS    | x86_64 (Intel)        | `ffmpeg-<version>-macos-x64.tar.gz`   | macOS 10.15 Catalina                            |

Each release additionally contains one
`ffmpeg-<version>-<platform>-<arch>.configure.txt` per target and a single
`checksums.sha256`. Every release body repeats this table with direct download
links and file sizes.

Each archive contains **exactly two files at its root**:

```
ffmpeg-9.0.1-linux-x64.tar.gz
├── ffmpeg
└── ffprobe
```

No nested directory, no headers, no static libraries, no shared objects, no docs
or man pages. Extract and run.

Verify a download with:

```sh
sha256sum -c checksums.sha256 --ignore-missing
```

---

## Intended use: subprocess, not linking

The static CLI releases are **standalone executables**. Their intended
consumption model - and the assumption the license analysis below rests on - is:

- the downstream application bundles `ffmpeg` / `ffprobe` as resource files;
- it invokes them as a **separate process** (`spawn`/`exec`/`CreateProcess`);
- it does **not** link `libavcodec`, `libavformat` or any other FFmpeg library
  into its own binary.

No `.dll`, `.so`, `.dylib`, `.a`, `.lib` or header file is published by this
release line, so linking against the CLI builds is not possible. The separately
labelled shared SDK below has a different dynamic-linking and compliance model.

### Minimum obligations for the downstream app

Not legal advice - confirm with your own counsel. In practice, for the model
described above:

1. **The LGPL relinking requirement does not apply.** Section 6 of LGPL-2.1
   covers works that are _linked_ with the library. Executing a separate process
   is not linking and does not create a combined work, so you are not obliged to
   ship object files, provide a relinking mechanism, or allow the user to
   substitute a modified FFmpeg. This is also why the binaries here are
   statically linked - static linking only matters for the relinking obligation
   that a subprocess model does not trigger.
2. **You still have to give notice.** State that your application uses FFmpeg,
   that FFmpeg is licensed under LGPL-2.1-or-later, and reproduce the LGPL-2.1
   license text (and the copyright notices of the bundled libraries listed
   above). An "About" dialog, a bundled `THIRD-PARTY-LICENSES` file, or an
   open-source-licenses screen all work. Linking to the corresponding FFmpeg
   source (the exact tag stated in the configure log of the release you ship)
   alongside the notice is the safest form.
3. **Do not modify the binaries.** If you ever patch FFmpeg itself, you must make
   those modifications available under the LGPL. Ship the unmodified release
   assets and this never comes up.
4. **Keep the audit trail.** Record which release tag you bundled; the matching
   `*.configure.txt` proves what was and was not compiled in.

Suggested notice text:

```
This application bundles FFmpeg (https://ffmpeg.org), used as a separate
executable and licensed under the GNU Lesser General Public License version 2.1
or later. FFmpeg source code for the exact version used is available at
https://github.com/FFmpeg/FFmpeg. A copy of the LGPL-2.1 is included in this
distribution.
```

---

## FFmpeg 8 shared SDK

The **Build FFmpeg shared SDK (LGPL)** workflow is a separate release pipeline
for dynamic-link consumers such as `rsmpeg 0.18`. It is pinned to FFmpeg 8.0.3
and produces dynamically linked SDK archives for the same five targets as the
static CLI pipeline.

Each archive contains:

- shared `avcodec`, `avdevice`, `avfilter`, `avformat`, `avutil`, `swresample`
  and `swscale` libraries;
- public headers for those seven libraries;
- relocatable pkg-config files and Windows import libraries;
- FFmpeg's LGPL license and notice files plus the zlib license.

The seven-library set is intentional: `rusty_ffmpeg 0.16.7+ffmpeg.8` probes all
seven even when an application directly calls only a subset.

The SDK uses `--disable-gpl --disable-nonfree --disable-version3`, together with
`--disable-static --enable-shared --disable-programs --disable-autodetect`. A
post-build test loads `libavutil`, verifies the runtime-reported FFmpeg version,
license and configuration, checks all seven development packages, and records
the dynamic dependencies of every library.

zlib 1.3.1 is built from pinned source as the SDK's sole third-party dependency
and is statically included so PNG corpus decoding works without another runtime
library. This is separate from the static CLI dependency prefix.

Release tags and assets use the `ffmpeg-8.0.3-shared-*` naming scheme, so they
cannot collide with the static CLI releases. Each release also includes the
exact signed upstream source archive and checksums.

### Building the shared SDK locally

```sh
export FFMPEG_TAG=n8.0.3
export VERSION=8.0.3
export ASSET_BASE=ffmpeg-8.0.3-shared-linux-x64
bash scripts/install-build-tools.sh
bash scripts/build-shared-sdk-deps.sh
bash scripts/build-shared-sdk.sh
bash scripts/verify-shared-sdk.sh
bash scripts/package-shared-sdk.sh
```

To publish all five targets, run **Build FFmpeg shared SDK (LGPL)** from the
Actions tab. Its release job runs only after every target passes verification.

For `rusty_ffmpeg`/`rsmpeg`, point `FFMPEG_PKG_CONFIG_PATH` at the extracted
`lib/pkgconfig` directory and set `FFMPEG_LINK_MODE=dynamic`.

---

## Audit evidence

Every release contains one `ffmpeg-<version>-<platform>-<arch>.configure.txt` per
target, produced by [`scripts/verify-license.sh`](scripts/verify-license.sh)
from the binary that was actually shipped. It records:

- the FFmpeg tag, target, host runner and build sysroot;
- the pinned version and license of every bundled third-party library;
- the complete configure option list, read back via `ffmpeg -buildconf`;
- the `ffmpeg -version` and `ffprobe -version` output;
- on Linux, the highest `GLIBC_*` symbol version the executables require, which
  is what substantiates the glibc 2.35 claim above;
- the dynamic library dependencies (`ldd` / `otool -L` / `objdump -p`).

These files are release assets, so they stay downloadable next to the binaries
they describe - a link into a CI log that expires is not enough for an audit.

---

## Building

### Via GitHub Actions

1. Actions → **Build FFmpeg (LGPL)** → **Run workflow**
2. `ffmpeg_version` - the FFmpeg git tag to build, e.g. `n9.0.1`
3. `draft_release` - create the release as a draft instead of publishing it
4. `rebuild_deps` - ignore the dependency cache and rebuild every library

All five targets build in parallel; the release is only cut once every target has
succeeded and passed the license gate. The release is tagged
`ffmpeg-<version>-build<run number>`, so re-running the same FFmpeg version never
collides with an existing tag.

The dependency prefix is cached per target and keyed on the hash of
`scripts/versions.sh`, so bumping a pinned version invalidates the cache while
editing a build script does not. If you change *how* a library is built, run the
workflow with `rebuild_deps` enabled to force a cold build - libaom dominates
that path.

### Locally

The same scripts run outside CI on Linux, macOS, and Windows under an MSYS2
UCRT64 shell:

```sh
export FFMPEG_TAG=n9.0.1
bash scripts/install-build-tools.sh    # apt / brew / pacman, build tools only
bash scripts/build-deps.sh             # third-party libraries, from source
bash scripts/build-ffmpeg.sh           # configure + make, into dist/
bash scripts/verify-license.sh         # license gate + configure log
bash scripts/package.sh                # archive with the two executables
```

Results land in `dist/`. Note that a local Linux build links against your own
glibc, so it will not carry the 2.35 floor that the CI container guarantees.

---

## Repository layout

```
.
├── .github/workflows/build.yml   # 5-target matrix, manual dispatch, release
├── .github/workflows/build-shared-sdk.yml # independent shared SDK release
├── scripts/
│   ├── versions.sh               # pinned dependency versions (the cache key)
│   ├── common.sh                 # platform detection, paths, toolchain env
│   ├── install-build-tools.sh    # toolchain per platform (build tools only)
│   ├── build-deps.sh             # third-party libraries, static, from source
│   ├── build-ffmpeg.sh           # configure options + build + binary extraction
│   ├── verify-license.sh         # license gate + audit report
│   ├── package.sh                # archive containing only ffmpeg + ffprobe
│   ├── release-notes.sh          # release body with the download table
│   ├── build-shared-sdk-deps.sh  # isolated, pinned zlib build
│   ├── build-shared-sdk.sh       # pinned FFmpeg 8 shared libraries
│   ├── verify-shared-sdk.sh      # SDK ABI/license/runtime audit
│   ├── package-shared-sdk.sh     # relocatable SDK archive
│   └── release-notes-shared-sdk.sh # shared SDK release body
└── README.md
```

### Build targets

| Target        | Runner             | Notes                                                                                                                                |
| :------------ | :----------------- | :----------------------------------------------------------------------------------------------------------------------------------- |
| `win-x64`     | `windows-latest`   | MSYS2 UCRT64, MinGW-w64. `-static` removes all runtime DLL dependencies.                                                             |
| `linux-x64`   | `ubuntu-latest`    | Built inside an `ubuntu:22.04` container to pin the glibc floor at 2.35.                                                             |
| `linux-arm64` | `ubuntu-24.04-arm` | Native arm64, no QEMU. Same 22.04 container.                                                                                         |
| `macos-arm64` | `macos-latest`     | `MACOSX_DEPLOYMENT_TARGET=11.0`                                                                                                      |
| `macos-x64`   | `macos-15-intel`   | `MACOSX_DEPLOYMENT_TARGET=10.15`. GitHub provides this image free until **August 2027**, after which it is scheduled for retirement. |

On Linux and macOS, "static" covers FFmpeg and every codec library; the system C
library stays dynamic, which is the only combination that works reliably on those
platforms. The Windows executables are fully static.

---

## Adding a library

1. Confirm the license is BSD/MIT/Apache style. **Anything GPL, nonfree, or
   version3-only is out** - it would fail `scripts/verify-license.sh` anyway.
2. Pin the version in `scripts/versions.sh` and add a `build_*` function to
   `scripts/build-deps.sh` producing a static archive in `$PREFIX`.
3. Add the matching `--enable-*` to `CONFIGURE_ARGS` in
   `scripts/build-ffmpeg.sh` - `--disable-autodetect` means an unlisted library
   is silently ignored.
4. Update the table in this README.
