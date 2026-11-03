# Test image (Ubuntu 22.04, the system of the official Haxe CI, whose package
# names RunCi expects). It only carries system tools and libraries: the
# language toolchains (Python, PyPy, Node.js...) come from the pinned archives
# of test-versions.env, installed by scripts/test/setup-tools.sh, as on macOS.
ARG TEST_IMAGE
FROM ${TEST_IMAGE}

RUN apt-get -o Acquire::Retries=5 update \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        bash ca-certificates curl git xz-utils bzip2 unzip zip file binutils \
        build-essential pkg-config cmake ninja-build \
    && git config --system --add safe.directory '*'

ENV BUILD_HAXE_IN_CONTAINER=1
WORKDIR /workspace
