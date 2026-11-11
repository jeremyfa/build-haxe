# build-haxe

Portable binaries of the Haxe compiler (`haxe`, `haxelib`, `std/`, neko) for macOS (universal), Linux (x64, arm64) and Windows (x64), built from any Haxe repository, branch or commit. Same scripts locally and on GitHub Actions, every version pinned, nothing installed outside this folder.

Technical details (portability, pinning, mirror, profiles, test setup) are in [INTERNALS.md](INTERNALS.md).

## Get binaries

[Releases](../../releases): one release per built commit, named `haxe-<profile>-<commit>` (`haxe5` is `development`, `haxe43` is `4.3_bugfix`), with an archive per platform. Each archive holds one `haxe/` folder that works wherever it is copied.

Nothing is built automatically when Haxe gets new commits: releases are published by hand (below).

## Publish a release

**Actions** > **Build Haxe** > **Run workflow**, or with `gh`:

```bash
gh workflow run build-haxe.yml -R jeremyfa/build-haxe -f ref=development   # Haxe 5
gh workflow run build-haxe.yml -R jeremyfa/build-haxe -f ref=4.3_bugfix    # Haxe 4.3

# a fork
gh workflow run build-haxe.yml -R jeremyfa/build-haxe \
  -f repo=https://github.com/me/haxe.git -f ref=my-branch

# build and test without publishing
gh workflow run build-haxe.yml -R jeremyfa/build-haxe -f ref=development -f publish=false
```

| Input | Default | |
|---|---|---|
| `repo` | official Haxe repository | any git URL |
| `ref` | `development` | branch or full commit; several separated by spaces |
| `profile` | `auto` | `haxe5` or `haxe43` to force one |
| `run_tests` | `all` | `all`, `default` (macro and neko), `none` |
| `publish` | on | off to only build and test |

The release is created only when the four builds and every test pass. A commit that already has a release is skipped; delete the release and its tag to rebuild it.

## Build locally

Requirements: Xcode Command Line Tools, Homebrew (`brew bundle`), Rosetta for x86_64, Docker for Linux. Windows builds only run on GitHub Actions.

```bash
./build-haxe-mac.sh              # macOS universal
./build-haxe-linux.sh arm64      # Linux arm64 (Docker)
./build-haxe-linux.sh x64        # Linux x64 (Docker)
./build-haxe-all.sh              # the three above
```

Output: `build/<profile>/<target>/<build id>/haxe/`, archive in `build/archives/`. The first build compiles OCaml and its packages (about 10 minutes); the rest is cached in `.cache/`.

Pick the sources:

```bash
HAXE_BRANCH=4.3_bugfix ./build-haxe-mac.sh
HAXE_REPO=https://github.com/me/haxe.git HAXE_BRANCH=my-branch ./build-haxe-mac.sh
HAXE_COMMIT=<sha> ./build-haxe-mac.sh
HAXE_SRC_DIR=/path/to/haxe ./build-haxe-mac.sh     # a local checkout, nothing is written in it
```

The clone lives in `haxe/`. To switch to another repository, delete `haxe/`, `haxe.info` and `haxe.files` first (not `./clean-haxe.sh`, which also deletes the 14 GB cache).

## Run the tests

```bash
./test-haxe.sh mac-universal              # macro and neko
./test-haxe.sh mac-universal all          # every target the profile supports
./test-haxe.sh linux-x64 js,cpp
./test-haxe-all.sh                        # all targets on macOS, Linux arm64 and x64
```

Results: `build/test-results/<profile>/<target>/<build id>/` (one log per target, `summary.md`). Linux runs in Docker; cs on macOS needs `brew bundle --file=Brewfile.tests`.

## Use from another project

Set `HAXE_SRC_DIR` (the sources), `HAXE_OUT_DIR` (where the binaries go) and optionally `BUILD_HAXE_CACHE_DIR`, then call the build scripts, or use the composite action `.github/actions/build-haxe` on GitHub. See [INTERNALS.md](INTERNALS.md#using-build-haxe-from-another-project).

## Update a dependency

Versions live in `versions.env` (build), `test-versions.env` (tests) and `profiles/<profile>/profile.env` (per branch overrides). Change the version and sha256, then push: the `Mirror dependencies` workflow uploads the new file to the [mirror](https://github.com/jeremyfa/haxe-deps). Changing OCaml or the opam snapshot also needs `scripts/update-locks.sh` (see [INTERNALS.md](INTERNALS.md#profiles)).
