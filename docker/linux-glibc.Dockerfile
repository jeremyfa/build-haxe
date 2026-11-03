# glibc image used to link haxelib against the official neko release,
# assemble and verify the Linux folder. docker/linux-test.Dockerfile adds the
# tools needed by the tests.
# Its glibc sets the minimum glibc of haxelib, so the oldest base that the
# neko release accepts is used (see GLIBC_IMAGE_* in versions.env):
#   x64:   Debian 11 (glibc 2.31), neko needs 2.29. Debian 11 is out of
#          support: packages come from a fixed snapshot.debian.org date.
#   arm64: Ubuntu 22.04 (glibc 2.35), neko needs 2.34.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG DEBIAN_SNAPSHOT=""

RUN if [ -n "${DEBIAN_SNAPSHOT}" ]; then \
        printf '%s\n' \
            "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye main" \
            "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bullseye-updates main" \
            "deb http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT} bullseye-security main" \
            > /etc/apt/sources.list; \
    fi \
    && apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Retries=5 update \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        bash gcc libc6-dev ca-certificates curl git file binutils patchelf zip unzip \
    && git config --system --add safe.directory '*'

ENV BUILD_HAXE_IN_CONTAINER=1
WORKDIR /workspace
