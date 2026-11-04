# Test image (Ubuntu 22.04, the system of the official Haxe CI, whose package
# names RunCi expects). It only carries system tools and libraries (HashLink
# and Lua rock dependencies, mono for the cs target of 4.3): the
# language toolchains (Python, PyPy, Node.js...) come from the pinned archives
# of test-versions.env, installed by scripts/test/setup-tools.sh, as on macOS.
ARG TEST_IMAGE
FROM ${TEST_IMAGE}

RUN apt-get -o Acquire::Retries=5 update \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        bash ca-certificates curl git xz-utils bzip2 unzip zip file binutils \
        build-essential pkg-config cmake ninja-build \
        libpng-dev libjpeg-turbo8-dev libturbojpeg0-dev zlib1g-dev libvorbis-dev \
        libsqlite3-dev libmbedtls-dev libuv1-dev \
        libpcre2-dev libssl-dev libreadline-dev libncurses-dev \
        mono-devel mono-mcs \
    && git config --system --add safe.directory '*'

# UTF-8 locale, as on the official CI runners: the sys tests use file names
# and arguments with non-ASCII characters, which Java (and others) encode with
# the locale.
ENV BUILD_HAXE_IN_CONTAINER=1 LANG=C.UTF-8 LC_ALL=C.UTF-8
WORKDIR /workspace
