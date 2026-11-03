# Build image for the static haxe binary (musl).
# The image only carries system tools. opam, the OCaml compiler, the C
# libraries and neko come from the pinned downloads in versions.env.
ARG ALPINE_IMAGE
FROM ${ALPINE_IMAGE}

# gcompat lets the official neko release (glibc) answer `neko -version`,
# which is all the conf-neko opam package checks. haxelib itself is built in
# the glibc image.
RUN apk add --no-cache \
        bash build-base cmake ninja git curl ca-certificates linux-headers \
        perl m4 patch unzip rsync pkgconf file binutils gcompat libgcc \
    && git config --system --add safe.directory '*'

ENV BUILD_HAXE_IN_CONTAINER=1
WORKDIR /workspace
