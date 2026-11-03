# Test image: the glibc build image plus the tools some macro tests call
# (node, python3, and a JDK for the Java test of 4.3_bugfix).
# Built on top of build-haxe-glibc:<arch> by test-haxe.sh.
ARG GLIBC_TAG
FROM ${GLIBC_TAG}

RUN DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        nodejs python3 default-jdk-headless
