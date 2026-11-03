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

Outputs go to `build/<profile>/<target>/<commit>/haxe/` and archives to `build/archives/haxe-<profile>-<commit>-<target>.{zip,tar.gz}`.

The first build of a target compiles OCaml and all the opam packages (about 10 minutes natively, more under Rosetta). Later builds reuse them.

## Choosing the Haxe repository, branch or commit

| Variable | Default | |
|---|---|---|
| `HAXE_REPO` | `https://github.com/HaxeFoundation/haxe.git` | repository to clone |
| `HAXE_BRANCH` | `development` | branch |
| `HAXE_COMMIT` | | exact commit, takes precedence over the branch |
| `HAXE_PROFILE` | detected | `haxe5` or `haxe43` |
| `SKIP_SETUP` | `0` | `1` builds `haxe/` as it is, without fetching |
| `SIGN_IDENTITY` | | macOS: sign with this Developer ID (hardened runtime) instead of ad hoc |

```bash
HAXE_BRANCH=4.3_bugfix ./build-haxe-mac.sh
HAXE_REPO=https://github.com/jeremyfa/haxe.git HAXE_BRANCH=new_csharp ./build-haxe-mac.sh
```

The clone lives in `haxe/`. To build from another repository, run `./clean-haxe.sh` first (the scripts refuse to switch the origin of an existing clone).

## neko and haxelib

neko is compiled from pinned sources by `scripts/build-neko.sh`, the same way neko's own CI does it (`cmake -DSTATIC_DEPS=all`, then its `package` target). Its dependencies (Boehm GC, zlib, mbedtls, pcre2, sqlite, MariaDB connector, OpenSSL) are linked statically. They are prefetched into `.cache/downloads` and checked against the sha256 that neko's CMake pins, with mirrors for the hosts that are often down (`archive.mariadb.org`, the OpenSSL GitHub releases). Each profile picks its neko source in `profile.env`:

- `haxe5`: neko master (`NEKO_MASTER_COMMIT`). The neko output of Haxe 5 uses primitives that no neko release has yet (2.4.1 is from April 2025).
- `haxe43`: the 2.4.1 release (`NEKO_RELEASE_COMMIT`).

haxelib comes from the `extra/haxelib_src` submodule of the Haxe repository, so its version follows the Haxe commit. The build compiles its client to neko bytecode with the freshly built `haxe` (`run.n`), then `nekotools boot` turns it into a small native launcher linked to libneko, with an rpath to the `neko/` folder next to it. haxelib is therefore exactly as portable as neko.

## Profiles

The two maintained Haxe branches need different OCaml dependencies. A profile is a folder in `profiles/`:

- `haxe5` for `development`: OCaml 5.3.0, mbedtls 3.6, ppx_parser.
- `haxe43` for `4.3_bugfix`: OCaml 5.1.1, mbedtls 2.28, camlp5, ctypes pinned to 0.21.1 (luv 0.5.13 does not build with newer ctypes, like on the official 4.3 CI).

The profile is detected from `haxe/haxe.opam`. Each profile has a `haxe.opam.locked` with the exact version of every opam package, resolved against a pinned snapshot of opam-repository (`OPAM_REPO_COMMIT` in `versions.env`). To update them:

```bash
HAXE_PROFILE=haxe5 scripts/update-locks.sh mac-arm64
HAXE_BRANCH=4.3_bugfix ./setup-haxe.sh && HAXE_PROFILE=haxe43 scripts/update-locks.sh mac-arm64
```

Each OCaml version gets its own opam root (`.cache/opam/<profile>-<target>-ocaml<version>`), so changing it never reuses an old one. `profiles/<profile>/patches/` can hold patches applied to the Haxe sources during the build and reverted afterwards. The file name prefix selects the platform (`all-`, `mac-`, `linux-`, `windows-`).

All other versions (opam, zlib, pcre2, mbedtls, neko sources, container images) and their checksums are in `versions.env`.

## Running tests

```bash
./test-haxe.sh mac-universal              # default suites of the profile
./test-haxe.sh linux-arm64 macro          # runs in docker/linux-test.Dockerfile
```

Default suites: `macro,neko` for both profiles. Tests run on a fresh copy of the clone in `build/test-work/` (inside the container for Linux). A few macro tests call node, python3 or Java: the Linux test image has them, on macOS they must be installed. Other RunCi targets (`js`, `hl`, `cpp`, `jvm`, `python`, `php`, `lua`) can be listed too, but need their own toolchain installed.

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

A build is skipped when the release `haxe-<profile>-<commit>` already exists. macOS arm64 and x86_64 are built in separate jobs and combined into a universal binary. Linux uses the same Docker images as local builds.
