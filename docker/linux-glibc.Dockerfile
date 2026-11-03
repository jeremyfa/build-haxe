# glibc image (Debian 11, glibc 2.31) used to build neko from source, link
# haxelib against it, and assemble and verify the Linux folder.
# Its glibc is the minimum glibc of neko and haxelib (haxe itself is static).
# docker/linux-test.Dockerfile adds the tools needed by the tests.
# Debian 11 is out of support: packages come from a fixed snapshot.debian.org
# date (GLIBC_SNAPSHOT in versions.env), which also makes the image
# reproducible.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG DEBIAN_SNAPSHOT

RUN printf '%s\n' \
        "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye main" \
        "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye-updates main" \
        "deb http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT} bullseye-security main" \
        > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Retries=5 update \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        bash gcc g++ make cmake ninja-build pkg-config perl autoconf automake libtool patch \
        libc6-dev ca-certificates curl git file binutils patchelf zip unzip \
    && git config --system --add safe.directory '*'

ENV BUILD_HAXE_IN_CONTAINER=1
WORKDIR /workspace
