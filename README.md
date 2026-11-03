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
  neko/           neko runtime used by haxelib (next to the executables on Windows)
  commit.txt      Haxe commit
  build_info.txt  versions of everything that went into the build
```

## What makes the binaries portable

- **macOS**: universal (arm64 + x86_64). `haxe` only links `libSystem` and the `Security` / `CoreFoundation` frameworks. zlib, pcre2 and mbedtls are compiled from source and linked statically, never taken from Homebrew. Minimum macOS: 11.0 (arm64), 10.13 (x86_64). `haxelib` and neko need macOS 11.0. Ad hoc signature by default.
- **Linux**: `haxe` is a fully static musl binary (built on Alpine): it runs on any distribution, including Alpine. `haxelib` uses the official neko release, which needs glibc: 2.31 or newer on x64 (Debian 11, Ubuntu 20.04 and later), 2.35 or newer on arm64 (Ubuntu 22.04, Debian 12 and later).
- **Windows**: `haxe.exe` only depends on system DLLs (C libraries and the mingw runtime are linked statically).

`scripts/verify-binary.sh` checks all of this after every build (linked libraries, minimum OS versions, architectures, signatures, and that `haxe --version` and `haxelib version` run with an empty environment). The Linux build also runs both in bare `alpine`, `debian` and `ubuntu` images.

## Building from Source

### Requirements

- macOS builds: Xcode Command Line Tools, [Homebrew](https://brew.sh) for host tools only (`brew bundle --file=Brewfile`: cmake, ninja, pkgconf), and Rosetta for x86_64 (`softwareupdate --install-rosetta`).
- Linux builds: Docker. On macOS, Docker Desktop is started automatically if needed and stopped at the end. Building x64 from an Apple Silicon Mac needs "Use Rosetta for x86_64/amd64 emulation" enabled in Docker Desktop.
- Windows builds: opam 2.2+ with a mingw OCaml switch (this is what GitHub Actions uses through `ocaml/setup-ocaml`).

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

## Profiles

The two maintained Haxe branches need different OCaml dependencies. A profile is a folder in `profiles/`:

- `haxe5` for `development`: OCaml 5.3.0, mbedtls 3.6, ppx_parser.
- `haxe43` for `4.3_bugfix`: OCaml 5.3.0, mbedtls 2.28, camlp5.

The profile is detected from `haxe/haxe.opam`. Each profile has a `haxe.opam.locked` with the exact version of every opam package, resolved against a pinned snapshot of opam-repository (`OPAM_REPO_COMMIT` in `versions.env`). To update them:

```bash
HAXE_PROFILE=haxe5 scripts/update-locks.sh mac-arm64
HAXE_BRANCH=4.3_bugfix ./setup-haxe.sh && HAXE_PROFILE=haxe43 scripts/update-locks.sh mac-arm64
```

`profiles/<profile>/patches/` can hold patches applied to the Haxe sources during the build and reverted afterwards. The file name prefix selects the platform (`all-`, `mac-`, `linux-`, `windows-`).

All other versions (opam, zlib, pcre2, mbedtls, neko, container images) and their checksums are in `versions.env`.

## Running tests

```bash
./test-haxe.sh mac-universal              # macro and neko test suites
./test-haxe.sh linux-arm64 macro,neko     # runs in the Debian build image
```

Other RunCi targets (`js`, `hl`, `cpp`, `jvm`, `python`, `php`, `lua`) can be listed too, but need their own toolchain installed.

## Known limits

- x86_64 macOS builds run the toolchain under Rosetta. Apple announced that its developer tools may stop being universal from version 27, which would break this. `scripts/check-host.sh` warns when the SDK reaches 27.
- `haxelib` on Linux needs glibc (the official neko release is not built for musl). `haxe` itself runs everywhere.
- Windows binaries are built on GitHub Actions or on a Windows machine. Cross-compiling them from a Mac is not supported.

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
