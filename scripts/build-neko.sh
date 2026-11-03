#!/usr/bin/env bash
# Build neko from pinned sources, with every dependency linked statically.
# Usage: scripts/build-neko.sh <target>
# Requires HAXE_PROFILE (selects the neko source, see NEKO_SOURCE).
# Output: build/neko/<neko name>/<target>/ with the flat layout of the official
# neko archives: neko, nekoc, nekoml, nekotools, libneko, *.ndll, include/.
#
# Same process as neko's own CI: `cmake -DSTATIC_DEPS=all`, then the
# `package` target. neko downloads and pins (sha256) its own dependencies:
# Boehm GC, zlib, mbedtls, pcre2, sqlite, MariaDB connector, OpenSSL.
# Modules that depend on system libraries are left out: ui.ndll (GTK) and
# mod_neko / mod_tora (Apache).
# mac-universal combines mac-arm64 and mac-x86_64 with lipo.
# On Linux it runs in the glibc image (its glibc is the minimum glibc of neko).
#
# patches/neko/*.patch are applied to the sources. They make a neko folder
# self-contained: modules (.ndll) are looked up next to libneko, then in
# NEKOPATH, never in global paths, and the binaries have no rpath to the
# global install prefix.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: build-neko.sh <target>}"
check_target "$target"
load_profile

os="$(target_os "$target")"
arch="$(target_arch "$target")"
dest="$(neko_dir "$target")"
min=""
if [ "$os" = "mac" ] && [ "$arch" != "universal" ]; then
    eval "min=\${MACOS_MIN_$arch}"
fi
patch_id="$(cat "$ROOT"/patches/neko/*.patch | (sha256sum 2>/dev/null || shasum -a 256) | cut -c1-12)"
want="$NEKO_COMMIT min=$min patches=$patch_id"
stamp="$dest/.done"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
    log "neko $NEKO_NAME for $target already built"
    exit 0
fi
# A folder from another source, other patches or an interrupted build is set
# aside (never deleted, see clean-haxe.sh).
if [ -e "$dest" ]; then
    old="$dest.old.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$old"
    log "previous neko folder moved to $old"
fi

# ---- macOS: another architecture runs under Rosetta
if [ "$os" = "mac" ] && [ "$arch" != "universal" ] && [ "$arch" != "$(uname -m)" ]; then
    exec /usr/bin/arch "-$arch" /bin/bash "$0" "$target"
fi

# ---- macOS universal: lipo the two architectures
if [ "$target" = "mac-universal" ]; then
    "$ROOT/scripts/build-neko.sh" mac-arm64
    "$ROOT/scripts/build-neko.sh" mac-x86_64
    a64="$(neko_dir mac-arm64)"
    x64="$(neko_dir mac-x86_64)"
    mkdir -p "$dest"
    cp -R -P "$a64/." "$dest/"
    for f in "$a64"/*; do
        name="$(basename "$f")"
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        if lipo -archs "$f" >/dev/null 2>&1; then
            lipo -create -output "$dest/$name.tmp.$$" "$f" "$x64/$name"
            mv -f "$dest/$name.tmp.$$" "$dest/$name"
        fi
    done
    echo "$want" > "$stamp"
    log "neko $NEKO_NAME ready: $dest"
    exit 0
fi

# ---- sources
work="$PRODUCTS_CACHE_DIR/neko-work/$NEKO_NAME-$patch_id/$target"
log "neko $NEKO_NAME: $NEKO_REPO at $NEKO_COMMIT"
if [ -n "$NEKO_URL" ]; then
    archive="$(download "$NEKO_URL" "$NEKO_SHA256")"
else
    archive="$(fetch_git_archive "$NEKO_ARCHIVE_NAME" "$NEKO_REPO" "$NEKO_COMMIT" "$NEKO_SHA256" "neko-$NEKO_COMMIT/")"
fi
src="$work/src"
if [ ! -d "$src" ]; then
    # The archive holds a single top-level folder, whatever its name.
    mkdir -p "$work/src.extract.$$"
    tar -xzf "$archive" -C "$work/src.extract.$$"
    top="$(find "$work/src.extract.$$" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [ -n "$top" ] && [ -f "$top/CMakeLists.txt" ] || die "$archive does not hold the neko sources"
    mv "$top" "$src"
    # Patches already merged in the sources (a fork) are skipped.
    for p in "$ROOT"/patches/neko/*.patch; do
        log "$(basename "$p"): $(apply_patch_once "$src" "$p")"
    done
fi
build="$work/build-src"
mkdir -p "$build"

# Prefetch the dependencies pinned in neko's CMakeLists (URL + URL_HASH) into
# the downloads cache (dependency mirror first, then the original host, then
# known alternative hosts), and place them where neko's ExternalProject looks
# first (it then skips the download).
mirrors_for() {
    local url="$1"
    case "$url" in
        https://downloads.mariadb.com/Connectors/c/*)
            echo "https://archive.mariadb.org/${url#https://downloads.mariadb.com/Connectors/c/}" ;;
        https://www.openssl.org/source/openssl-*.tar.gz)
            local f v
            f="$(basename "$url")"; v="${f%.tar.gz}"
            echo "https://github.com/openssl/openssl/releases/download/$v/$f" ;;
    esac
}
# neko_deps <neko sources>: prints "<url> <sha256>" for each pinned dependency.
# Also used by scripts/deps-manifest.sh.
neko_deps() {
    awk '/^[ \t]*URL[ \t]+https?:/{u=$2} /URL_HASH[ \t]+SHA256=/{sub(/.*SHA256=/,""); if(u!=""){print u, $1; u=""}}' \
        "$1/CMakeLists.txt" "$1"/libs/*/CMakeLists.txt
}
prefetch_deps() {
    local dl="$build/libs/download" url sha file cached candidate
    mkdir -p "$dl"
    neko_deps "$src" | while read -r url sha; do
        file="$(basename "$url")"
        if cached="$(download "$url" "$sha" 2>/dev/null)"; then
            cp -f "$cached" "$dl/$file"
            continue
        fi
        cached=""
        for candidate in $(mirrors_for "$url"); do
            if cached="$(download "$candidate" "$sha" "$file" 2>/dev/null)"; then break; fi
            cached=""
        done
        if [ -n "$cached" ]; then
            cp -f "$cached" "$dl/$file"
        else
            warn "could not prefetch $file, neko's CMake will try $url itself"
        fi
    done
}
prefetch_deps

cmake_args=(-DCMAKE_BUILD_TYPE=Release -DSTATIC_DEPS=all -DRELOCATABLE=ON
    -DWITH_UI=OFF -DWITH_APACHE=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

case "$os" in
    mac)
        # Only Apple tools and the Homebrew build tools, never Homebrew
        # libraries: neko must not find them through pkg-config or CMake.
        hostbin="$(prepare_hostbin)"
        export PATH="$hostbin:/usr/bin:/bin:/usr/sbin:/sbin"
        unset C_INCLUDE_PATH CPATH LIBRARY_PATH PKG_CONFIG_PATH DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH CFLAGS LDFLAGS || true
        export PKG_CONFIG_LIBDIR="$build/no-pkgconfig"
        export MACOSX_DEPLOYMENT_TARGET="$min"
        cmake_args+=(-G Ninja -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET="$min"
            -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local"
            -DCMAKE_C_FLAGS="-ffile-prefix-map=$src=neko")
        ;;
    linux)
        in_container || die "Linux neko is built in the glibc image (see build-haxe-linux.sh)"
        export PKG_CONFIG_LIBDIR="$build/no-pkgconfig"
        cmake_args+=(-G Ninja -DCMAKE_C_FLAGS="-ffile-prefix-map=$src=neko")
        ;;
    windows)
        # neko is built with MSVC on Windows, like the official releases.
        cmake_args+=(-G "Visual Studio 17 2022" -A x64)
        ;;
esac

log "configuring neko $NEKO_NAME for $target"
if [ "$os" = "windows" ]; then
    cmake -S "$(cygpath -w "$src")" -B "$(cygpath -w "$build")" "${cmake_args[@]}"
    # Dependency downloads are retried, as in neko's CI.
    for i in 1 2 3; do
        cmake --build "$(cygpath -w "$build")" --config Release --target download_deps && break
        [ "$i" -lt 3 ] || die "could not download neko dependencies"
    done
    cmake --build "$(cygpath -w "$build")" --config Release
    cmake --build "$(cygpath -w "$build")" --config Release --target PACKAGE
    pkg="$(ls "$build"/bin/neko-*-win64.zip "$build"/neko-*-win64.zip 2>/dev/null | head -1 || true)"
else
    cmake -S "$src" -B "$build" "${cmake_args[@]}"
    log "building neko $NEKO_NAME for $target"
    cmake --build "$build" --parallel "$JOBS"
    cmake --build "$build" --target package
    pkg="$(ls "$build"/bin/neko-*.tar.gz "$build"/neko-*.tar.gz 2>/dev/null | head -1 || true)"
fi
[ -n "$pkg" ] || die "neko package archive not found in $build"

# The archive contains one top-level folder with the flat layout.
extract="$work/package"
mkdir -p "$extract" "$dest"
case "$pkg" in
    *.zip) unzip -q -o "$pkg" -d "$extract" ;;
    *) tar -xzf "$pkg" -C "$extract" ;;
esac
top="$(find "$extract" -mindepth 1 -maxdepth 1 -type d -name 'neko-*' | head -1)"
[ -n "$top" ] || die "unexpected layout in $pkg"
cp -R -P "$top/." "$dest/"

"$dest/neko$([ "$os" = windows ] && echo .exe)" -version >/dev/null || die "the built neko does not run"
echo "$want" > "$stamp"
log "neko $NEKO_NAME ready: $dest ($("$dest/neko$([ "$os" = windows ] && echo .exe)" -version))"
