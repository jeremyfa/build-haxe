# build-haxe internals

How the binaries are made portable, what is pinned and where, and how the pieces fit. The [README](README.md) covers everyday use.

## Contents of an archive

```
haxe/
  haxe            the compiler
  haxelib
  std/            standard library (found next to the executable, no HAXE_STD_PATH needed)
  neko/           neko, built from source (next to the executables on Windows)
  commit.txt      Haxe commit
  build_info.txt  versions of everything that went into the build
```

## Portability

- **macOS**: universal (arm64 + x86_64). `haxe`, `haxelib` and neko only link `libSystem` and system frameworks: every C library is compiled from source and linked statically, never taken from Homebrew. Minimum macOS: 11.0 (arm64), 10.13 (x86_64). Ad hoc signature by default, `SIGN_IDENTITY` for a Developer ID.
- **Linux**: `haxe` is a fully static musl binary (built on Alpine) and runs on any distribution. neko and `haxelib` are built on Debian 11 and need glibc 2.31 or newer (Debian 11, Ubuntu 20.04 and later).
- **Windows**: `haxe.exe` only depends on system DLLs (C libraries and the mingw runtime are linked statically). neko is built with MSVC, like the official releases.

### Self-contained lookups

The `haxe/` folder never uses files installed elsewhere on the machine:

- `haxe` finds `std/` next to itself, and runs the `haxelib` next to itself: it puts its own folder first in the `PATH` of the processes it starts (`profiles/*/patches/all-haxelib-next-to-haxe.patch`), so `-lib`, hxcpp or hashlink never pick up another haxelib.
- `haxelib` finds libneko in `neko/` through a relative rpath (`@executable_path/neko`, `$ORIGIN/neko`).
- neko looks for its modules (`.ndll`) next to libneko, then in `NEKOPATH`, never in global folders such as `/usr/local/lib/neko` (`patches/neko/self-contained-lookup.patch`). No binary has an absolute rpath.

`scripts/verify-binary.sh` checks all of this after every build: linked libraries, minimum OS versions, architectures, signatures, and that `haxe --version` and `haxelib setup`, `list` and `version` run with an empty environment. Decoys prove the lookups (corrupted modules in `NEKOPATH`, a fake `haxelib` first in the `PATH`). The Linux build also runs the tools in bare `alpine`, `debian` and `ubuntu` images.

### Known limits

- x86_64 macOS builds run the toolchain under Rosetta. Apple announced that its developer tools may stop being universal from version 27. `scripts/check-host.sh` warns when the SDK reaches 27.
- neko and `haxelib` on Linux need glibc: neko loads its modules with `dlopen`, which a static binary cannot do.
- Windows binaries are built on GitHub Actions or on a Windows machine, not cross-compiled from a Mac.
- The neko build leaves out the modules that depend on system libraries: `ui.ndll` (GTK) and the Apache modules `mod_neko2` / `mod_tora2`.

## Build variables

| Variable | Default | |
|---|---|---|
| `HAXE_REPO` | `https://github.com/HaxeFoundation/haxe.git` | repository to clone |
| `HAXE_BRANCH` | `development` | branch |
| `HAXE_COMMIT` | | exact commit, takes precedence over the branch |
| `HAXE_PROFILE` | detected | `haxe5` or `haxe43` |
| `HAXE_SRC_DIR` | | build these sources instead of cloning |
| `HAXE_PROFILE_DIR` | | a profile folder of the caller |
| `HAXE_OUT_DIR` | | copy the result there, with stable names |
| `HAXE_LAYOUT` | `standard` | `ceramic` for haxe/ and neko/ side by side |
| `BUILD_HAXE_CACHE_DIR` | `.cache` and `build/` | where downloads, opam roots, neko and the C libraries are kept |
| `SKIP_SETUP` | `0` | `1` builds `haxe/` as it is, without fetching |
| `SIGN_IDENTITY` | | macOS: sign with this Developer ID (hardened runtime) instead of ad hoc |

Outputs go to `build/<profile>/<target>/<build id>/haxe/` and archives to `build/archives/haxe-<profile>-<build id>-<target>.{zip,tar.gz}`. The build id is the short commit, with `-dirty` when the sources have local changes.

Windows, on a machine with opam 2.2+ and a mingw switch, from its Cygwin bash: `opam exec -- bash ./build-haxe-windows.sh`.

### Local cache

Everything downloaded or compiled lands in `.cache/` (or `BUILD_HAXE_CACHE_DIR`): `downloads/` (every archive, checked by sha256), `opam/` (one opam root per profile, target and OCaml version), `deps/` and `neko/` (C libraries and neko per platform), `test-tools/` (test toolchains, git sources and mirrors), `home/` (the HOME of the tests). Each step leaves a `.done` marker and is skipped afterwards. A new version is installed next to the old one, nothing is replaced or removed. `./clean-haxe.sh` deletes `haxe/`, `.cache/`, `build/` and the Docker volumes after confirmation.

## Using build-haxe from another project

A project that has both `haxe` and `build-haxe` as git submodules can build its own Haxe, locally and on its CI.

| Variable | |
|---|---|
| `HAXE_SRC_DIR=/path/to/haxe` | Build these sources: no clone, no fetch. They are copied to `build/source/` (tracked and new files with their uncommitted changes, submodules included) and nothing is written in them, not even the git index. Every submodule must be initialized. With local changes the build id ends with `-dirty` and `build_info.txt` lists the changed files. |
| `HAXE_OUT_DIR=/path/to/out` | Copy the result to `$HAXE_OUT_DIR/<platform>/` and `$HAXE_OUT_DIR/haxe-<platform>.<zip or tar.gz>`. Files are replaced one by one through a new inode (macOS kills an executable overwritten in place) and nothing is deleted there. |
| `BUILD_HAXE_CACHE_DIR=/path/to/cache` | Keep the cache there, so the caller can save it (`actions/cache`). From macOS the Linux opam roots stay in a Docker volume per arch: the case-insensitive file system breaks the OCaml build. opam roots cannot be moved once created. |
| `HAXE_PROFILE_DIR=/path/to/profile` | A profile of the caller: `profile.env`, optionally `haxe.opam.locked` and `patches/`. With `PROFILE_BASE=auto` (or `haxe5`, `haxe43`) it extends the built-in profile: its settings win, its patches are applied after the built-in ones. `PROFILE_NAME` names it (default: the folder name). |

### Ceramic layout

With `--ceramic-layout` (or `HAXE_LAYOUT=ceramic`), the build also produces the layout of ceramic's `git/haxe-binary`: `haxe/` and `neko/` side by side, in folders named `mac`, `linux-x86_64`, `linux-arm64` and `windows`. `haxelib` finds libneko through an rpath to `../neko`. On Windows a DLL is only found next to the executable, so `haxe/` also holds the neko runtime that `haxelib.exe` needs, and `neko/` holds the full neko.

### Example

```
my-project/
  haxe/            submodule: the Haxe sources to build
  build-haxe/      submodule: this repository
  haxe-profile/    optional: profile.env (PROFILE_NAME=my-project, PROFILE_BASE=auto) and patches
  haxe-binary/     where the binaries go
```

```bash
export HAXE_SRC_DIR="$PWD/haxe"
export HAXE_OUT_DIR="$PWD/haxe-binary"
export HAXE_PROFILE_DIR="$PWD/haxe-profile"           # optional
export BUILD_HAXE_CACHE_DIR="$HOME/.cache/build-haxe"  # optional
build-haxe/build-haxe-mac.sh universal --ceramic-layout
build-haxe/build-haxe-linux.sh arm64 --ceramic-layout
```

On GitHub Actions, the composite action prepares the runner (Homebrew tools and Rosetta on macOS, Docker on Linux, `ocaml/setup-ocaml` on Windows), caches the toolchains and runs the script of the platform:

```yaml
jobs:
  haxe:
    strategy:
      fail-fast: false
      matrix:
        include:
          - { platform: mac-universal, runner: macos-15 }
          - { platform: linux-x64, runner: ubuntu-24.04 }
          - { platform: linux-arm64, runner: ubuntu-24.04-arm }
          - { platform: windows-x64, runner: windows-2025 }
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - id: haxe
        uses: ./build-haxe/.github/actions/build-haxe
        with:
          platform: ${{ matrix.platform }}
          source: haxe
          out-dir: haxe-binary
          profile: haxe-profile   # optional
          layout: ceramic
          run-tests: 'false'
      - uses: actions/upload-artifact@v4
        with:
          name: haxe-${{ matrix.platform }}
          path: ${{ steps.haxe.outputs.archive }}
```

Inputs: `platform` (required), `source` (path of the sources; when empty, `repo` and `ref` are cloned), `out-dir`, `profile` (a built-in name or a folder), `layout`, `cache` (default `true`), `cache-dir`, `run-tests`. Outputs: `folder`, `archive`, `build-id`, `out-folder`, `out-archive`.

## Profiles

The two maintained Haxe branches need different OCaml dependencies. A profile is a folder in `profiles/`, chosen with `HAXE_PROFILE` or detected from `haxe.opam` (`camlp5` means `haxe43`, `ppx_parser` means `haxe5`):

- `haxe5` for `development`: OCaml 5.3.0, mbedtls 3.6, ppx_parser.
- `haxe43` for `4.3_bugfix`: OCaml 5.1.1, mbedtls 2.28, camlp5, ctypes pinned to 0.21.1 (luv 0.5.13 does not build with newer ctypes) and pcre2 pinned to 8.0.4 (8.0.3 does not compile with the mingw gcc). Windows is built with OCaml 4.14.4 (`OCAML_VERSION_WINDOWS`), like the official 4.3 CI: the memory measurement of the compilation server (`libs/objsize`) walks the OCaml 4 heap and crashes with OCaml 5 on Windows.

How the files combine: `profile.env` is read first, then `versions.env` and `test-versions.env`. Every value is written `: "${VAR:=default}"`, so the first one read wins: the environment, then the profile, then the common files. `versions.env` holds several variants of some dependencies (`MBEDTLS2_*`/`MBEDTLS3_*`, `NEKO_MASTER_*`/`NEKO_RELEASE_*`) and the profile picks one (`MBEDTLS_SERIES`, `NEKO_SOURCE`). `HAXE_PROFILE=haxe43 scripts/deps-manifest.sh` lists what a profile ends up using.

Each profile has a `haxe.opam.locked` with the exact version of every opam package, resolved against the pinned snapshot of opam-repository (`OPAM_REPO_COMMIT`). A profile can build one OS with another OCaml (`OCAML_VERSION_<OS>`), with its own lock `haxe.opam.ocaml<version>.locked`. The locks are generated from an installed switch (not `opam lock`, which cannot handle the dependency formula of 4.3):

```bash
HAXE_PROFILE=haxe5 scripts/update-locks.sh mac-arm64
HAXE_BRANCH=4.3_bugfix ./setup-haxe.sh && HAXE_PROFILE=haxe43 scripts/update-locks.sh mac-arm64
BUILD_HAXE_FOR_OS=windows HAXE_PROFILE=haxe43 scripts/update-locks.sh mac-arm64   # the OCaml 4.14 lock
```

Each OCaml version gets its own opam root (`.cache/opam/<profile>-<target>-ocaml<version>`). `profiles/<profile>/patches/` holds patches applied to the Haxe sources during the build; the file name prefix selects the platform (`all-`, `mac-`, `linux-`, `windows-`). A patch already present in the sources is skipped (`already applied`); one that neither applies nor is present stops the build.

## neko and haxelib

neko is compiled from pinned sources by `scripts/build-neko.sh`, the way neko's own CI does it (`cmake -DSTATIC_DEPS=all`, then its `package` target), with its dependencies (Boehm GC, zlib, mbedtls, pcre2, sqlite, MariaDB connector, OpenSSL) linked statically. They are prefetched and checked against the sha256 that neko's CMake pins. Both profiles use neko master (`NEKO_MASTER_COMMIT`): the neko output of Haxe 5 uses primitives that no release has yet, and Haxe 4.3 passes the same suites with master as with 2.4.1. `NEKO_SOURCE=RELEASE` selects 2.4.1.

haxelib comes from the `extra/haxelib_src` submodule of Haxe. Its client is compiled to neko bytecode with the freshly built `haxe`, then `nekotools boot` turns it into a native launcher linked to libneko, with an rpath to the `neko/` folder next to it.

### neko from a fork

A neko source is a set of variables `NEKO_<SOURCE>_*` and `NEKO_SOURCE` picks one. Define one in the environment or in a profile:

```bash
export NEKO_SOURCE=MYFORK
export NEKO_MYFORK_REPO=https://github.com/me/neko
export NEKO_MYFORK_COMMIT=<full commit sha>
export NEKO_MYFORK_SHA256=<sha256 of the tar of the commit>
# optional: NEKO_MYFORK_URL (another source archive, file:// works), NEKO_MYFORK_NAME
```

The sha256 is that of the uncompressed tar of the commit, identical on every system: `git archive --format=tar --prefix=neko-<commit>/ <commit> | shasum -a 256`. The build folder is named after the source and the commit, so builds of different sources never mix.

## Dependency mirror

Every pinned dependency is also published, byte for byte, as an asset of a release of [jeremyfa/haxe-deps](https://github.com/jeremyfa/haxe-deps): `build-deps` for the build (opam binaries, zlib, pcre2, mbedtls, neko sources and what neko's CMake pins, the opam-repository snapshot, an archive of the opam package sources per lock), `test-deps` for the tests. `download()` looks in `.cache/downloads/` first, then the mirror, then the original location with a warning. The sha256 is checked either way: the mirror adds availability, never trust.

- Archives of git commits are made with `git archive | gzip -n`; the pinned sha256 is the one of the uncompressed tar, the same on every system.
- The opam source archive (`opam-cache-<profile>-<lock hash>.tar.gz`) is made with `opam admin cache` and used as opam's `archive-mirrors`. opam checks every file in it against the checksums of the pinned opam-repository.
- `BUILD_HAXE_MIRROR=none` skips the mirror, `BUILD_HAXE_MIRROR_ONLY=1` refuses any other source, `BUILD_HAXE_MIRROR` can point to another copy of the releases.

`scripts/deps-manifest.sh` lists every asset. `scripts/mirror-deps.sh` publishes what is missing and never replaces an asset; the `Mirror dependencies` workflow runs it on every push that changes a versions file or a profile (secret `HAXE_DEPS_TOKEN`). `scripts/mirror-deps.sh --check` reports missing or wrong assets; the build workflow runs it first and shows the result in its summary. For a new git dependency without sha256, `mirror-deps.sh` makes the archive, prints the sha256 to copy into the versions file and stops.

Not mirrored: Cygwin and setup-ocaml on Windows, Homebrew host tools.

### Docker images

The three Linux images (`docker/linux.Dockerfile` for the static haxe, `linux-glibc.Dockerfile` for neko and haxelib, `linux-test.Dockerfile` for the tests) are published on `ghcr.io/jeremyfa/build-haxe/<alpine|glibc|test>`, tagged `<arch>-<hash>`, where the hash covers the Dockerfile and its build arguments (base images pinned by digest, Debian snapshot date). `ensure_image` in `scripts/common.sh` uses the local image if present, otherwise pulls it, otherwise builds it (up to 5 tries, snapshot.debian.org has outages). The CI of build-haxe pushes the images it had to build (`BUILD_HAXE_PUSH_IMAGES=1`), so changing a Dockerfile builds the new image once. `BUILD_HAXE_IMAGE_REGISTRY=none` always builds locally.

## Tests

`test-haxe.sh` runs `tests/RunCi.hxml` of Haxe on a built folder, once per target, in a fresh copy of the sources. Linux runs in Docker (`docker/linux-test.Dockerfile`, Ubuntu 22.04 like the official CI). Results go to `build/test-results/<profile>/<target>/<build id>/`: one log and one status per target, `summary.md`, `results.json` and `env.txt`.

### What runs

| | development (`haxe5`) | 4.3_bugfix (`haxe43`) |
|---|---|---|
| macOS | macro neko js hl cpp jvm python php lua | macro neko js cpp java jvm cs python php |
| Linux x64 | macro neko js hl cpp jvm python php lua | macro neko js hl cpp java jvm cs python php lua |
| Linux arm64 | macro neko js hl cpp jvm python php lua | macro neko js cpp jvm python php lua |
| Windows x64 | macro neko js cpp jvm python php | macro neko js cpp java jvm cs python php |

`cpp` also runs the cppia tests. The lists follow the official CI of each branch (`FULL_TEST_TARGETS` and `TEST_SKIP_*` in the profiles), except:

- flash is not tested (the Flash Player is no longer distributed);
- hl on arm64 runs the HL/C tests only (`--skip-hl-jit`): HashLink has no VM on arm64;
- 4.3: hl is not tested on macOS (the official CI ran it on Intel Macs only);
- Windows: hl and lua are not set up yet;
- 4.3, cs on macOS is allowed to fail (`TEST_ALLOW_FAIL_*`): `misc/cs/csTwoLibs` does not compile with the mono 6.14 of Homebrew, it passes with the mono 6.8 of Linux.

A target is stopped after `TEST_TIMEOUT` seconds (default 2700) with the status `timeout`. On Windows, the php, node, python and java of the GitHub runners are taken out of `PATH` after ours: RunCi 4.3 uses every line of `where php` as the php path.

### How it stays pinned

RunCi installs part of what it needs by itself, from moving branches and into the home folder. `test-haxe.sh` prepares everything first, so RunCi only finds things already there:

- **Toolchains** come from the pinned archives of `test-versions.env`, installed in `.cache/test-tools/<platform>/`: Python (python-build-standalone) and PyPy, Node.js, a JDK (Temurin 21, Temurin 11 for 4.3), PHP (static-php-cli, the official build on Windows). HashLink and hxcpp are built from pinned commits; hererocks (Lua) runs from a pinned commit.
- **Repositories RunCi clones** (tink_core, hxcoro, java-lib-tests...) are redirected to local mirrors of pinned commits through the git configuration of the test home. The haxelib libraries (utest, hxnodejs, hxjava, hxcpp, hashlink...) are installed beforehand with `haxelib dev`.
- **npm**: deasync is installed from pinned package files.
- RunCi runs with `HOME` in the cache, `TZ=UTC`, a UTF-8 locale, and without `GITHUB_ACTIONS` even on GitHub: in CI mode it reinstalls libraries from their default branches and calls `sudo apt-get` and `brew`. The tests marked `#if github` (HTTP echo server, a few timezone checks) are therefore not run.

Not pinned yet: LuaJIT (rolling) and the rocks LuaRocks installs; the haxelib libraries that tink_core's tests take from lib.haxe.org; on macOS, the C libraries of the Lua rocks and mono (`Brewfile.tests`). Testing linux-x64 from an Apple Silicon Mac runs under Rosetta: the image is built without mono and LuaJIT 2.0 does not run there, so cs and part of lua only pass on a real x64 machine or on the CI.

## The build workflow

`.github/workflows/build-haxe.yml` runs every day at 03:00 UTC for `development` and `4.3_bugfix`, on pushes to `main` that change the build scripts, and by hand (`workflow_dispatch`). The `resolve` job turns the refs into commits and skips those that already have a release. One `build` job per platform uses the composite action (macOS universal on one arm64 runner, x86_64 under Rosetta; Linux in the same Docker images as local builds; Windows in the Cygwin of `ocaml/setup-ocaml`). One `test` job per build, platform and target runs on the archive the build made (`scripts/test/import-build.sh`, matrix from `scripts/test/test-matrix.sh`). `publish-release` runs only when every build and test job passed, for the daily run and for manual runs with `publish` checked: a push to `main` builds and tests, it never publishes. The Linux jobs pull their Docker images from ghcr.io (see [Docker images](#docker-images)).
