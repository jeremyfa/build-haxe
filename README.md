# build-haxe

Scripts to build portable binaries of the Haxe compiler (`haxe`, `haxelib` and the standard library) for macOS (universal), Linux (x64, arm64) and Windows (x64), from any Haxe repository, branch or commit. The same scripts run locally and on GitHub Actions. Every version is pinned and all the state stays inside this folder (no `sudo`, no `/usr/local`, no `~/.opam`).

## Prebuilt Binaries

See the [Releases](../../releases) page. The daily workflow builds the latest commit of `development` (Haxe 5) and `4.3_bugfix` (Haxe 4.3) and publishes a release `haxe-<profile>-<commit>` when that commit has not been built yet.

Each archive contains a single `haxe/` folder:

```
haxe/
  haxe            the compiler
  haxelib
  std/            standard library (found next to the executable, no HAXE_STD_PATH needed)
  neko/           neko, built from source (next to the executables on Windows)
  commit.txt      Haxe commit
  build_info.txt  versions of everything that went into the build
```

## What makes the binaries portable

- **macOS**: universal (arm64 + x86_64). `haxe`, `haxelib` and neko only link `libSystem` and system frameworks: every C library is compiled from source and linked statically, never taken from Homebrew. Minimum macOS: 11.0 (arm64), 10.13 (x86_64), for all binaries. Ad hoc signature by default.
- **Linux**: `haxe` is a fully static musl binary (built on Alpine): it runs on any distribution, including Alpine. neko and `haxelib` are built on Debian 11 and only need glibc 2.31 or newer (Debian 11, Ubuntu 20.04 and later), on x64 and arm64.
- **Windows**: `haxe.exe` only depends on system DLLs (C libraries and the mingw runtime are linked statically). neko is built with MSVC, like the official releases (the Windows build is only run on GitHub Actions).

### Self-contained

The `haxe/` folder works wherever it is copied and never uses files installed elsewhere on the machine:

- `haxe` finds `std/` next to itself, and runs the `haxelib` next to itself: it puts its own folder first in the `PATH` of the processes it starts (`profiles/*/patches/all-haxelib-next-to-haxe.patch`), so `-lib`, hxcpp or hashlink never pick up another haxelib.
- `haxelib` finds libneko in `neko/` through a relative rpath (`@executable_path/neko`, `$ORIGIN/neko`).
- neko looks for its modules (`.ndll`) next to libneko, then in `NEKOPATH`, and never in global folders such as `/usr/local/lib/neko` (`patches/neko/self-contained-lookup.patch`; on Windows it already looked next to `neko.dll`, the patch keeps that folder first when `NEKOPATH` is set). No binary has an absolute rpath.

`scripts/verify-binary.sh` checks all of this after every build (linked libraries, minimum OS versions, architectures, signatures, and that `haxe --version` and `haxelib setup`, `list` and `version` run with an empty environment). Decoys prove the lookups: haxelib must ignore corrupted modules put in `NEKOPATH`, and `haxe -lib` must ignore a fake `haxelib` put first in the `PATH`. The Linux build also runs the tools in bare `alpine`, `debian` and `ubuntu` images.

## Building from Source

### Requirements

- macOS builds: Xcode Command Line Tools, [Homebrew](https://brew.sh) for host tools only (`brew bundle --file=Brewfile`: cmake, ninja, pkgconf, autoconf, automake, libtool), and Rosetta for x86_64 (`softwareupdate --install-rosetta`).
- Linux builds: Docker. On macOS, Docker Desktop is started automatically if needed and stopped at the end. Building x64 from an Apple Silicon Mac needs "Use Rosetta for x86_64/amd64 emulation" enabled in Docker Desktop.
- Windows builds: opam 2.2+ with a mingw OCaml switch (this is what GitHub Actions uses through `ocaml/setup-ocaml`), plus CMake and Visual Studio 2022 for neko.

### macOS

```bash
./build-haxe-mac.sh              # universal (default)
./build-haxe-mac.sh arm64
./build-haxe-mac.sh x86_64       # built under Rosetta
```

### Linux (Docker)

```bash
./build-haxe-linux.sh arm64
./build-haxe-linux.sh x64
```

### Everything a Mac can build

```bash
./build-haxe-all.sh              # macOS universal, Linux arm64, Linux x64
```

### Windows

From the Cygwin bash of an opam installation with a mingw switch:

```bash
opam exec -- bash ./build-haxe-windows.sh
```

Outputs go to `build/<profile>/<target>/<build id>/haxe/` and archives to `build/archives/haxe-<profile>-<build id>-<target>.{zip,tar.gz}`, where the build id is the short commit, with `-dirty` when the sources have local changes. Add `--ceramic-layout` (or `HAXE_LAYOUT=ceramic`) to also get the [ceramic layout](#ceramic-layout).

The first build of a target compiles OCaml and all the opam packages (about 10 minutes natively, more under Rosetta). Later builds reuse them.

## Choosing the Haxe repository, branch or commit

| Variable | Default | |
|---|---|---|
| `HAXE_REPO` | `https://github.com/HaxeFoundation/haxe.git` | repository to clone |
| `HAXE_BRANCH` | `development` | branch |
| `HAXE_COMMIT` | | exact commit, takes precedence over the branch |
| `HAXE_PROFILE` | detected | `haxe5` or `haxe43` |
| `HAXE_SRC_DIR` | | build these sources instead of cloning (see [Using build-haxe from another project](#using-build-haxe-from-another-project)) |
| `HAXE_PROFILE_DIR` | | a profile folder of the caller (see [Profiles](#profiles)) |
| `HAXE_OUT_DIR` | | copy the result there, with stable names |
| `HAXE_LAYOUT` | `standard` | `ceramic` for haxe/ and neko/ side by side |
| `BUILD_HAXE_CACHE_DIR` | `.cache` and `build/` | where downloads, opam roots, neko and the C libraries are kept |
| `SKIP_SETUP` | `0` | `1` builds `haxe/` as it is, without fetching |
| `SIGN_IDENTITY` | | macOS: sign with this Developer ID (hardened runtime) instead of ad hoc |

```bash
HAXE_BRANCH=4.3_bugfix ./build-haxe-mac.sh
HAXE_REPO=https://github.com/jeremyfa/haxe.git HAXE_BRANCH=new_csharp ./build-haxe-mac.sh
```

The clone lives in `haxe/`. To build from another repository, run `./clean-haxe.sh` first (the scripts refuse to switch the origin of an existing clone).

## Using build-haxe from another project

build-haxe can build the Haxe sources of another project, for instance a project that has both `haxe` and `build-haxe` as git submodules, locally and on its CI. The environment variables below drive it; they work the same on every platform.

| Variable | |
|---|---|
| `HAXE_SRC_DIR=/path/to/haxe` | Build these sources: no clone, no fetch. They are copied to `build/source/` (tracked files and new files that are not ignored, with their uncommitted changes, submodules included) and nothing is ever written in them: git runs with `GIT_OPTIONAL_LOCKS=0`, so even the index is left untouched. Every submodule must be initialized in that folder, or the build stops and says which command to run. When the sources have local changes, the build id ends with `-dirty` and `build_info.txt` lists the changed files. On Linux, the copy is what the containers see (it lives in build-haxe, mounted on `/workspace`). |
| `HAXE_OUT_DIR=/path/to/out` | Copy the result to `$HAXE_OUT_DIR/<platform>/` and `$HAXE_OUT_DIR/haxe-<platform>.<zip or tar.gz>`. `<platform>` is the target (`mac-universal`, `linux-x64`, `linux-arm64`, `windows-x64`), or `mac`, `linux-x86_64`, `linux-arm64`, `windows` with the ceramic layout. Files are replaced one by one (through a new inode, so that macOS does not kill a replaced executable) and nothing is deleted there: files that a new build does not provide are reported and left in place. |
| `BUILD_HAXE_CACHE_DIR=/path/to/cache` | Keep downloads, opam roots, neko and the C libraries there instead of `.cache/` and `build/` of build-haxe, so the caller can cache them (with `actions/cache` on GitHub). On Linux the folder is mounted on `/cache`. The opam roots of the Linux builds go there on a Linux host (the CI); from macOS they stay in a Docker volume per arch, because the case-insensitive macOS file system breaks the OCaml build. opam roots cannot be moved once created: keep the path stable. |
| `HAXE_PROFILE_DIR=/path/to/profile` | A profile of the caller: `profile.env`, optionally `haxe.opam.locked` and `patches/`. With `PROFILE_BASE=auto` (or `haxe5`, `haxe43`) in its `profile.env`, it extends the built-in profile matching the sources: its settings win, its patches are applied after the built-in ones, and the built-in lock is used unless it has its own. `PROFILE_NAME` names it (default: the folder name); the name keys the opam roots and the outputs. |

### Ceramic layout

With `--ceramic-layout` (or `HAXE_LAYOUT=ceramic`), the build also produces the layout of ceramic's `git/haxe-binary`: `haxe/` and `neko/` side by side, in folders named `mac`, `linux-x86_64`, `linux-arm64` and `windows`. Lookups stay relative: `haxelib` finds libneko through an rpath to `../neko` on macOS and Linux. On Windows a DLL is only found next to the executable, so `haxe/` also holds the neko runtime that `haxelib.exe` needs (`neko.dll`, the `.ndll` modules and their DLLs), and `neko/` holds the full neko. `verify-binary.sh` checks this layout too (relative rpaths, haxelib with an empty environment and decoy modules).

### Example: haxe and build-haxe as submodules

```
my-project/
  haxe/            submodule: the Haxe sources to build (possibly with local changes)
  build-haxe/      submodule: this repository
  haxe-profile/    optional: profile.env and patches of my-project
  haxe-binary/     where the binaries go
```

`haxe-profile/profile.env`, if the project needs its own patches:

```bash
PROFILE_NAME=my-project
PROFILE_BASE=auto
```

Locally, from `my-project/`:

```bash
git submodule update --init --recursive

export HAXE_SRC_DIR="$PWD/haxe"
export HAXE_OUT_DIR="$PWD/haxe-binary"
export HAXE_PROFILE_DIR="$PWD/haxe-profile"         # optional
export BUILD_HAXE_CACHE_DIR="$HOME/.cache/build-haxe" # optional, keeps the toolchains between clones

build-haxe/build-haxe-mac.sh universal --ceramic-layout
build-haxe/build-haxe-linux.sh arm64 --ceramic-layout
build-haxe/build-haxe-linux.sh x64 --ceramic-layout
# haxe-binary/mac, haxe-binary/linux-arm64, haxe-binary/linux-x86_64
```

On GitHub Actions, with the composite action of build-haxe (`.github/actions/build-haxe`). It prepares the runner (Homebrew tools and Rosetta on macOS, Docker on Linux, `ocaml/setup-ocaml` on Windows), caches the toolchains, and runs the script of the platform:

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

Inputs of the action: `platform` (required), `source` (path of the Haxe sources; when empty, `repo` and `ref` are cloned), `out-dir`, `profile` (a built-in name or the path of a profile folder), `layout` (`standard` or `ceramic`), `cache` (default `true`), `cache-dir`, `run-tests`. Outputs: `folder`, `archive`, `build-id`, `out-folder`, `out-archive`. The workflow of build-haxe itself (`.github/workflows/build-haxe.yml`) uses the same action.

## neko and haxelib

neko is compiled from pinned sources by `scripts/build-neko.sh`, the same way neko's own CI does it (`cmake -DSTATIC_DEPS=all`, then its `package` target). Its dependencies (Boehm GC, zlib, mbedtls, pcre2, sqlite, MariaDB connector, OpenSSL) are linked statically. They are prefetched into `.cache/downloads` and checked against the sha256 that neko's CMake pins: from the [dependency mirror](#dependency-mirror) first, then the original hosts, then alternative hosts for those that are often down (`archive.mariadb.org`, the OpenSSL GitHub releases). Each profile picks its neko source in `profile.env`:

Both profiles use neko master (`NEKO_MASTER_COMMIT`): the neko output of Haxe 5 uses primitives that no neko release has yet (2.4.1 is from April 2025), and Haxe 4.3.7 passes exactly the same `macro` and `neko` suites with master as with 2.4.1 (same tests, same assertion counts, on macOS universal, Linux arm64 and Linux x64). The 2.4.1 release stays available: `NEKO_SOURCE=RELEASE`.

haxelib comes from the `extra/haxelib_src` submodule of the Haxe repository, so its version follows the Haxe commit. The build compiles its client to neko bytecode with the freshly built `haxe` (`run.n`), then `nekotools boot` turns it into a small native launcher linked to libneko, with an rpath to the `neko/` folder next to it. haxelib is therefore exactly as portable as neko.

## Using forks of Haxe and neko

Both can come from forks, with or without the patches of build-haxe merged.

**Haxe**: point `HAXE_REPO` (with `HAXE_BRANCH` or `HAXE_COMMIT`) to the fork, or `HAXE_SRC_DIR` to a checkout of it.

```bash
HAXE_REPO=https://github.com/me/haxe.git HAXE_BRANCH=my-branch ./build-haxe-mac.sh
```

**neko**: a neko source is a set of variables `NEKO_<SOURCE>_*` (see `versions.env`), and `NEKO_SOURCE` picks one. Define one for the fork, in the environment or in a profile of yours (`HAXE_PROFILE_DIR`):

```bash
export NEKO_SOURCE=MYFORK
export NEKO_MYFORK_REPO=https://github.com/me/neko
export NEKO_MYFORK_COMMIT=<full commit sha>
export NEKO_MYFORK_SHA256=<sha256 of the tar of the commit, see below>
# optional: NEKO_MYFORK_URL (another source archive, file:// works; its sha256
# then goes in NEKO_MYFORK_SHA256), NEKO_MYFORK_NAME
./build-haxe-mac.sh
```

The sha256 is that of the uncompressed tar of the commit, which `git archive` writes identically on every system: `git -C <clone of the fork> archive --format=tar --prefix=neko-<commit>/ <commit> | shasum -a 256`. The repository can be any git URL, not only GitHub. The archive is taken from the dependency mirror when it is there, otherwise made from the repository, and checked against this sha256 either way. The values of `versions.env` can be overridden the same way (`NEKO_MASTER_COMMIT=...`). The build folder is named after the source and the commit (`myfork-1a2b3c4`), so builds of different sources never mix.

**Patches already merged**: every patch (`patches/neko/` for neko, `patches/` of the profiles for Haxe) is skipped when the sources already contain it, and the log says `<patch>: already applied`. A patch that neither applies nor is present stops the build. This behaves the same with the BSD `patch` of macOS and with GNU `patch` (Linux, Cygwin): both are called with `-f`, without which BSD `patch` takes an unapplied patch for an applied one. The checks of `verify-binary.sh` (decoy modules in `NEKOPATH`, decoy `haxelib` in the `PATH`) then tell whether the merged changes do their job.

## Dependency mirror

Every pinned dependency is also published, byte for byte, as an asset of a release of [jeremyfa/haxe-deps](https://github.com/jeremyfa/haxe-deps): `build-deps` for the build (opam binaries, zlib, pcre2, mbedtls, neko sources and the dependencies neko's CMake pins, the opam-repository snapshot, and an archive of the opam package sources of each profile's lock), `test-deps` for the test suite. Downloads try the mirror first and the original location only if the mirror fails, with a warning; the sha256 is checked either way, so the mirror only adds availability, never trust.

- Archives of git commits (neko, opam-repository) are made with `git archive | gzip -n`. Their pinned sha256 is the one of the uncompressed tar, which is the same on every system, so an archive made from the repository when the mirror is unreachable is checked just as strictly.
- The opam source archive (`opam-cache-<profile>-<lock hash>.tar.gz`) is made with `opam admin cache` from the packages of the lock and used as opam's `archive-mirrors`. It has no pinned sha256: opam checks every file in it against the checksums of the pinned opam-repository.
- `BUILD_HAXE_MIRROR=none` skips the mirror, `BUILD_HAXE_MIRROR_ONLY=1` refuses any other source (to check that the mirror is complete), `BUILD_HAXE_MIRROR` can also point to another copy of the releases.

`scripts/deps-manifest.sh` lists every asset. After changing a pinned version, run `scripts/mirror-deps.sh` (or let the `Mirror dependencies` workflow do it, with the `HAXE_DEPS_TOKEN` secret): it publishes what is missing and never replaces an asset. `scripts/mirror-deps.sh --check` only reports missing or wrong assets; the build workflow runs it first and shows the result in its summary.

Not mirrored: the Docker base images (pinned by digest), the packages installed in them, Cygwin and setup-ocaml on Windows, Homebrew host tools.

## Profiles

The two maintained Haxe branches need different OCaml dependencies. A profile is a folder in `profiles/`:

- `haxe5` for `development`: OCaml 5.3.0, mbedtls 3.6, ppx_parser.
- `haxe43` for `4.3_bugfix`: OCaml 5.1.1, mbedtls 2.28, camlp5, ctypes pinned to 0.21.1 (luv 0.5.13 does not build with newer ctypes, like on the official 4.3 CI).

Both build neko from the same master commit.

A calling project can also give its own profile folder with `HAXE_PROFILE_DIR` (see above). Otherwise the profile is detected from `haxe.opam`. Each profile has a `haxe.opam.locked` with the exact version of every opam package, resolved against a pinned snapshot of opam-repository (`OPAM_REPO_COMMIT` in `versions.env`). To update them:

```bash
HAXE_PROFILE=haxe5 scripts/update-locks.sh mac-arm64
HAXE_BRANCH=4.3_bugfix ./setup-haxe.sh && HAXE_PROFILE=haxe43 scripts/update-locks.sh mac-arm64
```

Each OCaml version gets its own opam root (`.cache/opam/<profile>-<target>-ocaml<version>`), so changing it never reuses an old one. `profiles/<profile>/patches/` can hold patches applied to the Haxe sources during the build (with `patch -p1`, to a copy or reverted afterwards). The file name prefix selects the platform (`all-`, `mac-`, `linux-`, `windows-`).

All other versions (opam, zlib, pcre2, mbedtls, neko sources, container images) and their checksums are in `versions.env`.

## Running tests

`test-haxe.sh` runs the test suites of Haxe (`tests/RunCi.hxml`) on a built folder, for every target the profile supports:

```bash
./test-haxe.sh mac-universal              # DEFAULT_TEST_TARGETS of the profile (macro,neko)
./test-haxe.sh mac-universal all          # the full suite of the profile on this platform
./test-haxe.sh linux-x64 js,cpp           # a list of RunCi targets
./test-haxe-all.sh                        # full suite: macOS universal, Linux arm64 and x64
```

Linux runs in Docker (`docker/linux-test.Dockerfile`, Ubuntu 22.04 like the official CI). Results go to `build/test-results/<profile>/<target>/<build id>/`: one log and one status per test target, `summary.md`, `results.json` and `env.txt` (versions of every tool used).

### What runs

| | development (`haxe5`) | 4.3_bugfix (`haxe43`) |
|---|---|---|
| macOS | macro neko js hl cpp jvm python php lua | macro neko js cpp java jvm cs python php |
| Linux x64 | macro neko js hl cpp jvm python php lua | macro neko js hl cpp java jvm cs python php lua |
| Linux arm64 | macro neko js hl cpp jvm python php lua | macro neko js cpp jvm python php lua |
| Windows x64 | macro neko js cpp jvm python php | macro neko js cpp java jvm cs python php |

`cpp` also runs the cppia tests. The lists follow the official CI of each branch (`FULL_TEST_TARGETS` and `TEST_SKIP_*` in `profiles/*/profile.env`), with these differences:
- flash is not tested (the Flash Player is no longer distributed);
- hl on arm64 runs the HL/C tests only (`--skip-hl-jit`): HashLink has no VM on arm64;
- 4.3: hl is not tested on macOS (the official CI ran it on Intel Macs only; the HashLink 1.x VM is x86_64 and its libraries came from Homebrew);
- Windows: hl and lua are not set up by build-haxe yet.
- 4.3, cs on macOS is allowed to fail: one test (`misc/cs/csTwoLibs`) does not compile with the mono 6.14 of Homebrew; it passes with the mono 6.8 of Linux.

### How it stays pinned and self-contained

RunCi installs part of what it needs by itself, from moving branches and into the home folder. `test-haxe.sh` prepares everything first, so RunCi only finds things already there:

- **Toolchains** come from the pinned archives of `test-versions.env` (sha256, mirrored in the `test-deps` release of the [dependency mirror](#dependency-mirror)), installed in `.cache/test-tools/<platform>/`: Python (python-build-standalone) and PyPy, Node.js, a JDK (Temurin 21, Temurin 11 for 4.3, whose class reader does not read newer class files), PHP (static-php-cli builds, the official build on Windows), hererocks for Lua. HashLink and hxcpp are built from pinned commits.
- **Repositories RunCi clones** (tink_core, hxcoro, java-lib-tests...) and installs with `haxelib git` are redirected to local mirrors of pinned commits through the git configuration of the test home folder. The haxelib libraries (utest, hxnodejs, hxjava, hxcpp, hashlink...) are installed beforehand with `haxelib dev`.
- **npm**: deasync (sys tests of js) is installed from pinned package files, never from the registry.
- RunCi runs once per test target, in a fresh copy of the sources, with `HOME` in the cache, `TZ=UTC`, a UTF-8 locale, and **without `GITHUB_ACTIONS`**, even on GitHub: in CI mode RunCi reinstalls libraries from their default branches and calls `sudo apt-get` and `brew`. The tests marked `#if github` (HTTP echo server, a few timezone checks) are therefore not run.

Not pinned yet:
- Lua: hererocks downloads Lua, LuaJIT and LuaRocks, and LuaRocks installs the rocks (some from `scm` rockspecs).
- The haxelib libraries that tink_core's tests install from lib.haxe.org.
- On macOS, the C libraries of the Lua rocks and mono for cs come from Homebrew: `brew bundle --file=Brewfile.tests`.

### On GitHub Actions

Each build is tested by one job per platform and test target, on the archive the build job made (`scripts/test/import-build.sh`, matrix from `scripts/test/test-matrix.sh`). The release is published only when every test job passes. `workflow_dispatch` has a `run_tests` choice: `all` (default), `default` or `none`.

## Known limits

- x86_64 macOS builds run the toolchain under Rosetta. Apple announced that its developer tools may stop being universal from version 27, which would break this. `scripts/check-host.sh` warns when the SDK reaches 27.
- neko and `haxelib` on Linux need glibc: neko loads its modules (`.ndll`) with `dlopen`, which a static binary cannot do. `haxe` itself runs everywhere.
- Windows binaries are built on GitHub Actions or on a Windows machine. Cross-compiling them from a Mac is not supported.
- The neko build leaves out the modules that depend on system libraries: `ui.ndll` (GTK) and the Apache modules `mod_neko2` / `mod_tora2`.

## Cleaning up

```bash
./clean-haxe.sh
```

Deletes `haxe/`, `.cache/`, `build/` and the Docker volumes used for the Linux opam roots, after confirmation.

## Automated Builds

`.github/workflows/build-haxe.yml` runs:

- every day, for the latest commit of `development` and `4.3_bugfix`;
- on pushes to `main` that change the build scripts;
- manually (`workflow_dispatch`), with any repository, branch or commit, profile, and options to run tests and publish.

A build is skipped when the release `haxe-<profile>-<commit>` already exists. Each platform is built by the composite action `.github/actions/build-haxe`, the one a calling project uses (macOS universal on one arm64 runner, x86_64 under Rosetta). Linux uses the same Docker images as local builds.
