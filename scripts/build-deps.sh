#!/usr/bin/env bash
# Build zlib, pcre2 and mbedtls from pinned sources as static libraries.
# Usage: scripts/build-deps.sh <target>
# Requires HAXE_PROFILE (selects the mbedtls series).
# Output: build/deps/<profile>/<target>/{include,lib}

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: build-deps.sh <target>}"
check_target "$target"
load_profile
sanitize_env "$target"

os="$(target_os "$target")"
arch="$(target_arch "$target")"
prefix="$(deps_prefix "$target")"
work="$(deps_work "$target")"
stamp="$prefix/.done"
want="zlib=$ZLIB_VERSION pcre2=$PCRE2_VERSION mbedtls=$MBEDTLS_VERSION min=${MACOSX_DEPLOYMENT_TARGET:-}"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
    log "C dependencies for $HAXE_PROFILE/$target already built ($want)"
    exit 0
fi
if [ -e "$prefix" ]; then
    die "$prefix exists but does not match ($want). Remove it (or run ./clean-haxe.sh) and retry."
fi

mkdir -p "$prefix/include" "$prefix/lib/pkgconfig" "$work"

# extract <archive> -> prints the source directory
extract() {
    local archive="$1" name
    name="$(basename "$archive")"
    name="${name%.tar.gz}"; name="${name%.tar.bz2}"
    if [ ! -d "$work/$name" ]; then
        log "extracting $name" >&2
        mkdir -p "$work/$name.extract"
        tar -xf "$archive" -C "$work/$name.extract"
        mv "$work/$name.extract/$name" "$work/$name"
    fi
    echo "$work/$name"
}

CFLAGS_EXTRA="-O2 -fPIC"
CMAKE_COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF)
if [ "$os" = "mac" ]; then
    CFLAGS_EXTRA="$CFLAGS_EXTRA -arch $arch -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
    CMAKE_COMMON+=(-DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
        -DCMAKE_FIND_FRAMEWORK=NEVER -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local")
fi

cmake_build() {
    local src="$1" build="$2"
    shift 2
    cmake -S "$src" -B "$build" "${CMAKE_COMMON[@]}" "$@"
    cmake --build "$build" --parallel "$JOBS"
    cmake --install "$build"
}

# Windows: the mingw toolchain lives in the Cygwin environment set up by
# setup-ocaml. Plain makefiles and autotools are used there instead of CMake.
MINGW=x86_64-w64-mingw32

# ---- zlib
src="$(extract "$(download "$ZLIB_URL" "$ZLIB_SHA256")")"
log "building zlib $ZLIB_VERSION"
if [ "$os" = "windows" ]; then
    make -C "$src" -f win32/Makefile.gcc PREFIX="$MINGW-" libz.a
    cp "$src/libz.a" "$prefix/lib/"
    cp "$src/zlib.h" "$src/zconf.h" "$prefix/include/"
    cat > "$prefix/lib/pkgconfig/zlib.pc" <<EOF
prefix=$(cygpath -m "$prefix")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: zlib
Description: zlib compression library
Version: $ZLIB_VERSION
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF
else
    # zlib's own configure builds only libz.a with --static (its CMake
    # build always produces the shared library as well).
    (
        cd "$src"
        if [ -f Makefile ]; then make distclean >/dev/null 2>&1 || true; fi
        CFLAGS="$CFLAGS_EXTRA" ./configure --static --prefix="$prefix" --libdir="$prefix/lib"
        make -j"$JOBS" libz.a
        make install
    )
fi

# ---- pcre2
src="$(extract "$(download "$PCRE2_URL" "$PCRE2_SHA256")")"
log "building pcre2 $PCRE2_VERSION"
if [ "$os" = "windows" ]; then
    (
        mkdir -p "$work/pcre2-build"
        cd "$work/pcre2-build"
        "$src/configure" --host="$MINGW" --prefix="$prefix" --disable-shared --enable-static \
            --enable-pcre2-8 --disable-pcre2-16 --disable-pcre2-32 --enable-jit --enable-unicode \
            --disable-pcre2grep-libz --disable-pcre2grep-libbz2 --disable-pcre2test-libreadline
        make -j"$JOBS" libpcre2-8.la
        make install-libLTLIBRARIES install-includeHEADERS install-nodist_includeHEADERS install-pkgconfigDATA
    )
else
    cmake_build "$src" "$work/pcre2-build" \
        -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=OFF \
        -DPCRE2_SUPPORT_JIT=ON -DPCRE2_SUPPORT_UNICODE=ON -DPCRE2_BUILD_PCRE2GREP=OFF \
        -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_LIBZ=OFF -DPCRE2_SUPPORT_LIBBZ2=OFF \
        -DPCRE2_SUPPORT_LIBREADLINE=OFF -DPCRE2_SUPPORT_LIBEDIT=OFF
fi

# ---- mbedtls
src="$(extract "$(download "$MBEDTLS_URL" "$MBEDTLS_SHA256")")"
log "building mbedtls $MBEDTLS_VERSION"
if [ "$os" = "windows" ]; then
    make -C "$src/library" -j"$JOBS" CC="$MINGW-gcc" AR="$MINGW-ar" WINDOWS_BUILD=1 \
        libmbedcrypto.a libmbedx509.a libmbedtls.a
    cp "$src/library/libmbedcrypto.a" "$src/library/libmbedx509.a" "$src/library/libmbedtls.a" "$prefix/lib/"
    cp -R "$src/include/mbedtls" "$prefix/include/"
    if [ -d "$src/include/psa" ]; then cp -R "$src/include/psa" "$prefix/include/"; fi
else
    cmake_build "$src" "$work/mbedtls-$MBEDTLS_VERSION-build" \
        -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DGEN_FILES=OFF \
        -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
        -DMBEDTLS_FATAL_WARNINGS=OFF
fi

# ---- check: static archives only
for lib in libz.a libpcre2-8.a libmbedtls.a libmbedx509.a libmbedcrypto.a; do
    [ -f "$prefix/lib/$lib" ] || die "missing $prefix/lib/$lib"
done
shared="$(find "$prefix/lib" \( -name '*.dylib' -o -name '*.so' -o -name '*.so.*' -o -name '*.dll' -o -name '*.dll.a' \) -print)"
[ -z "$shared" ] || die "shared libraries found in $prefix/lib: $shared"

echo "$want" > "$stamp"
log "C dependencies ready in $prefix"
