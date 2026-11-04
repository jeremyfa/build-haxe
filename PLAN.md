# build-haxe : plan pour un build reproductible et portable du compilateur Haxe

Ce document est autonome. Il contient l'état des lieux, les décisions prises, l'architecture visée et les étapes à exécuter. Il a été rédigé le 2026-11-03 à partir des dépôts Haxe (`development` et `4.3_bugfix`), des workflows officiels de HaxeFoundation, et des projets build-sdl3 (clone local `../build-sdl`), build-angle (GitHub `jeremyfa/build-angle`), `../loreline-writer` et `../ceramic` qui servent de modèles. La section 0 liste ce qu'une vérification a corrigé par rapport à la première version.

## 0. Corrections vérifiées (2026-11-03)

La première version de ce document s'appuyait sur des clones locaux qui ne correspondaient pas à leur description. Corrections, et décisions prises pendant l'implémentation :

| Point | Réalité | Conséquence dans les scripts |
|---|---|---|
| `../haxe` décrit comme le fork `new_csharp` avec un `setup-mac.sh` | Clone upstream `development` d'avril 2023, sans `haxe.opam` ni `setup-mac.sh`. Le fork existe sur GitHub mais n'est cloné nulle part | Les faits sur `development` viennent du clone frais fait par `setup-haxe.sh` |
| `../haxe4` décrit comme le tag 4.3.7 | 3 commits locaux au-dessus du tag | Le profil haxe43 vise upstream `4.3_bugfix` |
| `~/.opam` : OCaml 5.4.0 | Switch unique `haxe4`, OCaml 5.1.1, opam 2.6.0 | Sans effet : le projet a ses propres racines opam |
| development dépend de `conf-libpcre2-8` | Il dépend du paquet opam `pcre2` (bindings OCaml), qui interroge `pkg-config libpcre2-8` à l'installation. `libs/pcre2` n'existe plus | `PKG_CONFIG_LIBDIR` pointe uniquement sur `build/deps/...` ; les deps C sont construites avant le switch |
| 4.3 : `HAXELIB_LDFLAGS` | La variable s'appelle `HAXELIB_LFLAGS` sur 4.3, `HAXELIB_LDFLAGS` sur development | haxelib est construit par `scripts/build-haxelib.sh`, sans `make haxelib` |
| 4.3 : frameworks ajoutés par le Makefile | Passer `LIB_PARAMS` en ligne de commande écrase le `+=` des frameworks | Les frameworks sont ajoutés par `build-core.sh` pour haxe43 |
| haxelib Linux lié au neko depuis Alpine | neko est lié à glibc (il charge ses modules avec `dlopen`), impossible à lier depuis musl | neko et haxelib sont construits dans une image Debian 11 (glibc 2.31) ; haxe reste statique musl |
| Alpine fournit neko pour `conf-neko` | Pas de paquet `neko` dans Alpine 3.22 | `gcompat` dans l'image Alpine : notre neko (glibc) répond à `neko -version`, seul test de `conf-neko` |
| Debian 11 via les dépôts normaux | Fin du LTS en août 2026, des paquets disparaissent des miroirs | Dépôts figés sur snapshot.debian.org (`DEBIAN_SNAPSHOT`) |
| haxelib : un seul sous-module | haxelib a ses propres sous-modules (hx3compat, hx4compat, crypto, record-macros) | `git submodule update --init --recursive` |
| Windows 4.3 : pcre2 statique | `pcre2.h` déclare les symboles `dllimport` sans `PCRE2_STATIC` | Patch `profiles/haxe43/patches/windows-pcre2-static.patch` |
| Build via `make haxe` | Un même clone sert à mac arm64, mac x86_64 et Linux | `build-core.sh` appelle `dune` comme la cible `haxe` de chaque Makefile, avec un `DUNE_BUILD_DIR` par cible |
| Sortie `build/<profil>/<cible>/haxe/` | Les scripts ne suppriment jamais de dossier | Sortie par commit : `build/<profil>/<cible>/<commit>/haxe/` |
| `build-haxe-windows.ps1` | opam sous Windows passe de toute façon par Cygwin | `build-haxe-windows.sh` lancé dans le bash Cygwin de setup-ocaml, avec le même `common.sh` |
| Lock opam unique | Les paquets virtuels de plateforme (`host-arch-*`, `host-system-*`) diffèrent selon l'hôte | `update-locks.sh` les retire ; sous Windows, les épinglages du compilateur sont retirés (il vient de setup-ocaml) |
| Clone bind-monté dans Docker | Le système de fichiers macOS est insensible à la casse, dune sous Linux échoue parfois | Le build Linux compile depuis une copie des sources dans le conteneur (`BUILD_HAXE_COPY_SOURCES=1`) |
| `run.n` de haxelib | Fichier suivi par git dans le sous-module, réécrit par chaque build | Restauré après le build de haxelib et avant tout changement de commit |
| Tests dans le clone | Certains tests écrivent dans l'arbre et ne supportent pas d'être relancés (Issue12873) | `test-haxe.sh` travaille sur une copie des fichiers suivis par git |
| Quelques tests macro | Des tests appellent node (`resolution`), python3 (`TestUnicode`) ou Java (`Issue11737` sur 4.3) | Image de test `docker/linux-test.Dockerfile` avec nodejs, python3 et un JDK |
| haxe43 sur OCaml 5.3.0 | luv 0.5.13 ne compile pas avec ctypes >= 0.22 et un clang récent ; ctypes 0.21.1 exige OCaml < 5.2 | Profil haxe43 : OCaml 5.1.1 et `OPAM_PINS="ctypes.0.21.1"`, comme le CI officiel de 4.3 |
| mbedtls 2.28 et CMake 4 | `cmake_minimum_required` trop ancien | `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` |
| Racine opam par profil et cible | Changer de version d'OCaml demanderait de supprimer la racine (et une racine opam n'est pas déplaçable) | Racine par profil, cible et version d'OCaml |
| neko : release officielle téléchargée | La std de development utilise des primitives neko de 2026 (`std@lock_create`...) absentes de 2.4.1 ; le neko arm64 officiel exige glibc 2.34 et macOS 11.0 | neko compilé depuis les sources (`scripts/build-neko.sh`, `STATIC_DEPS=all` comme le CI de neko) : master épinglé pour haxe5, tag 2.4.1 pour haxe43. Linux : Debian 11 sur les deux arches (glibc 2.29 requis au plus) ; mac : minos 10.13 en x86_64. Modules `ui`, `mod_neko2`, `mod_tora2` exclus |
| Sortie assemblée réutilisée | Un nouvel assemblage dans le même dossier laissait des fichiers de l'ancien | Assemblage dans un dossier neuf ; l'ancien est renommé `<commit>.old.<date>` |
| Autonomie du dossier `haxe/` (objectif) | neko gardait un rpath `/usr/local/lib` et cherchait ses `.ndll` dans `/usr/local/lib/neko`, `/usr/lib/neko`... ; `haxe -lib` lançait le premier `haxelib` du `PATH` | `patches/neko/self-contained-lookup.patch` (modules à côté de libneko, puis `NEKOPATH`, aucun chemin global ; plus de rpath global) et `profiles/*/patches/all-haxelib-next-to-haxe.patch` (le dossier de `haxe` en tête du `PATH` de ses sous-processus). Vérifié par des leurres dans `verify-binary.sh` |
| Téléchargements des dépendances de neko | `downloads.mariadb.com` en panne (erreur 522) a bloqué le build de neko 2.4.1 | `build-neko.sh` pré-télécharge chaque paire `URL`/`URL_HASH` des CMakeLists de neko dans `.cache/downloads`, avec miroirs (`archive.mariadb.org`, releases GitHub d'OpenSSL) ; noms temporaires uniques par processus, les builds parallèles partageant le cache |
| Usage comme dépendance d'un autre projet | Un projet appelant (Ceramic) veut builder son propre submodule haxe, en local et sur son CI | `HAXE_SRC_DIR` (copie lecture seule, `-dirty`), `HAXE_OUT_DIR` (noms stables), `BUILD_HAXE_CACHE_DIR`, `HAXE_PROFILE_DIR` (`PROFILE_BASE`), layout ceramic complet (Windows compris), action composite `.github/actions/build-haxe` utilisée aussi par le workflow de build-haxe. Les patches passent par `patch -p1` et `GIT_CEILING_DIRECTORIES` est posé pour qu'aucun outil ne remonte vers un dépôt parent |
| Forks de Haxe et de neko | Pouvoir construire depuis ses propres forks, patches déjà intégrés ; `build-neko.sh` appliquait ses patches avec `patch --forward`, qui échoue (code 1, BSD comme GNU) sur des sources déjà patchées | Sources neko décrites par `NEKO_<S>_REPO`, `_COMMIT`, `_SHA256` (et `_URL`, `_NAME` optionnels), surchargeables par l'environnement ou un profil ; `apply_patch_once` (common.sh) saute tout patch déjà présent, pour Haxe comme pour neko, testé avec le `patch` BSD de macOS et GNU 2.7.6 / 2.8 |
| Un seul neko pour les deux profils | haxe43 utilisait neko 2.4.1 | Avec neko master, Haxe 4.3.7 passe exactement les mêmes suites `macro` et `neko` (mêmes tests, mêmes nombres d'assertions) sur mac universal, Linux arm64 et x64, et toutes les vérifications de `verify-binary.sh` : haxe43 passe à `NEKO_SOURCE=MASTER`. La source `RELEASE` reste dans `versions.env` pour revenir en arrière |
| Copie d'exécutables avec `cp` | Écraser un exécutable sur place (même inode) fait tuer le binaire par macOS au lancement suivant (signature en cache) | `replace_file` : copie temporaire puis `mv`, pour opam, haxe, haxelib et neko |
| Passer d'une branche à l'autre dans le même clone | Le build 4.3 laisse `lib.sexp` et `src/compiler/version.ml` (ignorés par git), qui entrent en conflit avec les règles dune de development | `build-core.sh` les supprime avant un build haxe5 |

## 1. Objectif

Un projet `build-haxe`, sur le modèle de `build-sdl3` et `build-angle`, qui :

- récupère un dépôt Haxe (officiel ou fork, branche ou commit au choix) ;
- compile `haxe`, `haxelib` et embarque `std` ;
- lance les tests du dépôt ;
- produit les binaires de toutes les plateformes : macOS universal (arm64 + x86_64), Linux x64 et arm64, Windows x64 ;
- fonctionne en local depuis un Mac Apple Silicon (cross ou conteneurs) et sur GitHub Actions avec les mêmes scripts ;
- épingle toutes les versions et garde son état dans le dossier du projet (pas de `/usr/local`, pas de `sudo`, pas de `~/.opam`).

### Décisions prises

| Sujet | Décision |
|---|---|
| Homebrew | Accepté pour builder Haxe (outils de l'hôte : cmake, ninja, pkg-config, et au besoin un compilateur ou mingw), à condition d'être vérifié et épinglé. Contrainte absolue : le binaire `haxe` final doit être le plus portable possible. Les libs C (zlib, pcre2, mbedtls) sont donc compilées depuis les sources et liées statiquement, jamais prises dans `/opt/homebrew`, et aucune dylib brew ne doit apparaître dans `otool -L`. |
| Linux depuis le Mac | Docker Desktop (c'est ce que `loreline-writer/export-linux.sh` utilise déjà). |
| Linux libc | Binaire `haxe` statique musl (Alpine). Tourne sur toute distribution. |
| Windows | Build natif sur le CI en premier (setup-ocaml mingw, libs C statiques). Cross-compilation depuis le Mac en phase 3, expérimentale. |
| Branches | `development` (Haxe 5) et `4.3_bugfix` supportées dès le départ, via deux profils de dépendances. |

## 2. État des lieux

### 2.1 Les deux branches

| | 4.3_bugfix (tag 4.3.7, 2025-05) | development (Haxe 5, 2026-03) |
|---|---|---|
| OCaml | `>= 5.0` ou `>= 4.08 & < 5.0` (CI : 4.14.0 Windows, 5.1.1 mac, 4.14.0 et 5.3.0 Linux) | `>= 5.0` (domainslib). CI : 5.3.0 partout |
| dune | `>= 1.11 & < 3.16`, build avec `--workspace dune-workspace.dev` | `>= 3.17`, build avec `--profile release` |
| Parser | camlp5 (`camlp5o -impl grammar.mly`, `src/syntax/dune`). Sur OCaml < 5 : `camlp5 = 8.03.04` et `ocamlfind = 1.9.1` | ppx_parser `>= 0.2.0` |
| Deps opam communes | sedlex >= 2.0, xml-light, extlib >= 1.7.8, sha, camlp-streams, conf-libpcre2-8, conf-zlib, conf-neko | idem |
| Deps spécifiques | ptmap >= 2.0.0, `luv = 0.5.13` | luv >= 0.5.13, ipaddr, terminal_size, domainslib >= 0.5.2, saturn, thread-local-storage, dynamic_gc |
| Flags de lien | `Makefile:66-81` : `LIB_PARAMS` écrit dans `lib.sexp`, inclus par `src/dune` | règle dune `src/dune:42-54` qui lance `src/prebuild.ml libparams` et lit les **variables d'environnement** `STATICLINK` et `LIB_PARAMS` |
| mbedtls | 2.x (mac CI : 2.28.5, Windows : 2.16.3). Les stubs gèrent aussi 3.x | 3.6.x (`extra/BUILDING.md` : 4.x non supporté) |
| Windows | x64 et x86, Cygwin, DLLs mingw embarquées (`cygcheck`) | x64 seul, `setup-ocaml@v3` mingw, OCaml 5.3, DLLs embarquées |
| libs/ | extc, extlib-leftovers, ilib, javalib, json, mbedtls, neko, objsize, pcre2, swflib, ttflib, ziplib | ilib, javalib, ttflib supprimés (le fork `jeremyfa/haxe` ré-ajoute ilib pour le C#) |
| Tests | `macro` inclut les tests display (`tests/display`), un `nekotools server` est lancé pour toutes les cibles, cibles java et cs présentes | display déplacés dans `tests/server` (cible `js`, nécessite node), plus hxb et hxcoro, java et cs retirés |
| `haxe.opam` version | dit "4.3.6" (faux) | dit "4.3.0" (faux) |

Points communs :

- Libs C nécessaires : **zlib, pcre2, mbedtls**. Les fichiers dune ne passent aucun chemin d'include ni de lib et il n'y a pas de pkg-config : les headers et libs doivent être dans les chemins par défaut du compilateur, ou dans `C_INCLUDE_PATH` / `LIBRARY_PATH`. Les paquets `conf-*` ne font que vérifier la présence.
- libuv est vendorée et liée statiquement par `luv` (`libuv.a`). Pas de dépendance runtime.
- `conf-neko` exécute seulement `neko -version` : il faut neko dans le PATH au moment du `opam install`, et `--assume-depexts` pour éviter que opam cherche un paquet système.
- **haxelib** : `haxe client.hxml` produit `run.n`, puis `nekotools boot -c run.n` produit `run.c`, lié avec `-lneko` (`Makefile` cible `haxelib_unix`). Sur Windows, `nekotools boot run.n` produit `run.exe`. Il faut neko (headers, lib, `nekotools`) au build et `libneko` au runtime. Sur mac, le rpath est `$(INSTALL_DIR)/lib` via `HAXELIB_LDFLAGS`, surchargeable.
- Stubs C compilés par dune : `libs/pcre2/pcre2_stubs.c`, `libs/mbedtls/mbedtls_stubs.c`, `libs/extc/extc_stubs.c` (zlib), `libs/objsize/c_objsize.c`.
- Bug connu sur development : `prebuild.ml` teste `Option.is_some (Sys.getenv_opt "STATICLINK")`, donc `STATICLINK=0` active quand même le lien statique. Sur macOS, `STATICLINK` n'a aucun effet : seul `LIB_PARAMS` compte.
- Le `Makefile` de development hardcode `dune` au lieu de `$(DUNE_COMMAND)` pour la cible `haxe`.

### 2.2 Comment le CI officiel construit les releases

Fichier : `.github/workflows/main.yml` (sur 4.3, il est généré depuis `extra/github-actions/workflows/main.yml` et des templates qui ont dérivé ; sur development, il est écrit à la main avec des actions composites dans `.github/actions/{setup-neko,setup-ocaml-windows,cache-lua}`).

**Neko** : téléchargé depuis `https://build.haxe.org/builds/neko/$PLATFORM/neko_latest.{tar.gz,zip}` et symlinké dans `/usr/local/{bin,lib,include,lib/neko}`.

**Linux** (x64 : `ubuntu-22.04`, arm64 : `ubuntu-22.04-arm`, natif) :
```
apt: opam libpcre2-dev zlib1g-dev libgtk2.0-dev libmbedtls-dev ninja-build
opam init -c 5.3.0
opam pin add haxe . --no-action
opam install haxe --deps-only --assume-depexts
make -s -j$(nproc) STATICLINK=1 haxe
make -s haxelib
make -s package_unix
```
`STATICLINK=1` donne `-Wl,-Bstatic -lpcre2-8 -lz -lmbedtls -lmbedx509 -lmbedcrypto -Wl,-Bdynamic` : libs C statiques mais **glibc dynamique** (>= 2.35 environ). Le tarball `package_unix` n'embarque pas neko.

**macOS** (development : les deux arches sur `macos-latest`, qui est arm64) :
- `MACOSX_DEPLOYMENT_TARGET` = 11.0 (arm64) ou 10.13 (x86_64).
- zlib 1.3.1, mbedtls 3.6.4, pcre2 10.45 compilés **depuis les sources** avec `cmake -DCMAKE_OSX_ARCHITECTURES=<arch>`, installés avec `sudo` dans `/usr/local`.
- Pour x86_64 : téléchargement du binaire `opam-2.3.0-x86_64-macos`. Comme opam est un process x86_64 sous Rosetta, l'OCaml qu'il construit est x86_64.
- Build :
  ```
  make -s STATICLINK=1 "LIB_PARAMS=\"/usr/local/lib/libz.a\" \"/usr/local/lib/libpcre2-8.a\" \"/usr/local/lib/libmbedtls.a\" \"/usr/local/lib/libmbedcrypto.a\" \"/usr/local/lib/libmbedx509.a\"" haxe
  ```
  (prebuild ajoute `-framework Security -framework CoreFoundation` sur macOS ; sur 4.3, il faut les passer soi-même dans `LIB_PARAMS`).
- Un job `mac-build-universal` fait `lipo -create -output haxe macX64Binaries/haxe macArmBinaries/haxe` (idem haxelib), puis `make package_unix package_installer_mac PACKAGE_INSTALLER_MAC_ARCH=universal`.
- Brew sert seulement aux outils (`tests/Brewfile` : ninja, cmake, pkg-config, libunistring).
- Sur 4.3, le build x64 utilisait `macos-13`, runner retiré depuis.

**Windows** (`windows-latest`, x64) :
- `ocaml/setup-ocaml@v3`, mingw-w64, Cygwin interne d'opam (`CYG_ROOT: C:\cygwin`).
- mbedtls via un tarball prébuilt `Simn/mingw64-mbedtls` (3.6.5 sur dev, 2.16.3 sur 4.3), extrait avec `tar -C /`.
- `opam install` dans une action retry (10 essais), `OPAMEXTERNALSOLVER: builtin-mccs+glpk` pour éviter des libs 32 bits, un hack PATH pour luv#162.
- `make -f Makefile.win haxe`, puis `haxelib`, puis `package_bin package_installer_win package_choco`.
- Le zip embarque `zlib1.dll`, `libpcre2-8-0.dll`, `libmbed{crypto,tls,x509}.dll` trouvées avec `cygcheck`. **Pas de lien statique.**

### 2.3 Pourquoi le setup local actuel est fragile

- `~/.opam/default` : un seul switch, OCaml 5.4.0, dune 3.20.2, luv 0.5.14. Il compile development mais **pas 4.3.7** (dune < 3.16, luv = 0.5.13, camlp5 et ptmap manquants).
- `../haxe/setup-mac.sh` exporte `C_INCLUDE_PATH`, `LIBRARY_PATH` et `DYLD_LIBRARY_PATH` vers `brew --prefix zlib/pcre2/mbedtls@3` et `/usr/local/lib/neko`. Résultat (`otool -L ../haxe/haxe`) : un binaire lié dynamiquement à `/opt/homebrew/opt/pcre2/lib/libpcre2-8.0.dylib`, `libz.1.dylib`, `libmbed{tls.21,x509.7,crypto.16}.dylib`, avec `minos 26.0`. Non distribuable.
- `brew install mbedtls` donne aujourd'hui mbedtls 4.x, que ni 4.3 ni development ne supportent.
- Neko est installé globalement dans `/usr/local/lib/neko`.

### 2.4 Les projets modèles

- **build-sdl3 / build-angle** : scripts `setup-<lib>-<platform>.sh` (clone shallow, commit épinglé par variable d'env, écrit `.<lib>_commit`) et `build-<lib>-<platform>.sh [arch]`. Sortie dans `build/<platform>/<arch>/`, mac universal par `lipo`, archives `<lib>-mac-universal.zip`, `<lib>-linux-{x64,arm64}.tar.gz`, `<lib>-windows-{x64,arm64}.zip`. CI : job `get-<lib>-commit` qui saute le build si la release `<lib>-<short>` existe, matrice `macos-14`, `windows-2025`, `ubuntu-22.04` / `ubuntu-22.04-arm`, job `publish-release` avec `gh release create`. `build-angle/README.md` est le modèle de README.
- **loreline-writer/export-linux.sh** lignes 156 à 239 : détection et démarrage de Docker Desktop (`open -a Docker`, attente de `docker info` jusqu'à 90 s), arrêt en fin de script. Lignes 282 à 303 : `docker build --platform linux/<amd64|arm64>` puis `docker run --rm --platform ... -v "$SCRIPT_DIR:/workspace"` avec des volumes nommés par arch pour les caches. À reprendre tel quel.
- **ceramic/git/haxe-binary** : layout de destination `{mac,linux-x86_64,linux-arm64,windows}/{haxe,neko}`. `fix-mac-binaries.sh` met le rpath de haxelib à `@executable_path/../neko` et signe. `fix-linux-binaries.sh` met le RUNPATH à `$ORIGIN/../neko` avec patchelf.
- ceramic cross-compile Windows avec clang + xwin (MSVC). **Ne s'applique pas** à OCaml : le port mingw est ce qu'utilise Haxe officiellement.

### 2.5 État de l'art cross-compilation OCaml (recherche 2026-11)

- **OCaml 5.4.0** (2025-10) intègre les cross-compilateurs upstream (`./configure --target=x86_64-w64-mingw32`, `make crossopt`, `make installcross`). **OCaml 5.5.0** (2026-06) ajoute un compilateur relocatable, utile pour des toolchains locales au projet. Le CI upstream ne teste que Linux comme hôte (vers mingw-w64, aarch64-linux-gnu, Android), jamais macOS.
- **opam-cross-windows** (github.com/ocaml-cross/opam-cross-windows) est maintenu (OCaml jusqu'à 5.5.x) et supporte officiellement macOS arm64 comme hôte, cible Windows x86_64. Déjà portés : sedlex, xml-light, camlp-streams, ipaddr, saturn, ctypes, dune-configurator. **Manquants** : extlib, sha, pcre2, luv, domainslib, thread-local-storage, dynamic_gc, terminal_size, ppx_parser, camlp5. Alternative : vendorer avec opam-monorepo et `dune build -x windows`.
- **Blocage principal : luv.** Son `src/c/dune` compile un `generate_types_step_2.exe` avec le compilateur C de la cible puis **l'exécute** pour générer les layouts de structs (pattern ctypes). En cross, il faut wine (Windows) ou qemu-user (Linux), ou bien pré-générer `luv_c_generated_types.ml` sur une vraie machine cible et le réinjecter.
- **zig cc** : fonctionne pour Linux -> aarch64-linux-gnu (et permet de choisir la version de glibc), échoue pour Windows (flexdll attend les noms d'outils mingw et `windres`) et pour macOS. Expérimental.
- **llvm-mingw** (github.com/mstorsjo/llvm-mingw) publie des tarballs macOS universels avec `x86_64-w64-mingw32-gcc` et `windres`. flexdll >= 0.43 a un support clang. Aucun rapport publié de build OCaml 5 + llvm-mingw : plausible, non prouvé.
- **Linux statique** : opam construit ses propres releases sur un seul Mac arm64 avec des images Alpine par arch (`ghcr.io/kit-ty-kate/alpine:<arch>-v3.21`), OCaml compilé dans l'image, lien `-static`. dune-bin utilise Nix `pkgsCross.musl64`. semgrep est statique sur Alpine. Attention : à partir de OCaml 5.1 le runtime peut dépendre de zstd (vérifier avec `ldd`/`nm` ; sur Alpine ajouter `zstd-static` ou l'option `ocaml-option-no-compression`).
- **macOS x86_64 depuis arm64** : trois options. (1) runner `macos-15-intel` jusqu'à fin 2027. (2) Rosetta : opam x86_64 ou `arch -x86_64` (ce que font Haxe et opam). Avertissement du readme de release opam : à partir de macOS 27 / Command Line Tools 27, les outils système d'Apple ne sont plus universels et cette méthode casse. (3) Vrai cross-compilateur OCaml >= 5.4 `--target x86_64-apple-darwin` avec `CC="clang -arch x86_64"`, non testé upstream mais celui qui durera.
- **Windows sans Cygwin** : le port MSVC d'OCaml 5.3 existe mais le build d'OCaml lui-même a toujours besoin d'un shell Cygwin. opam 2.2+ natif Windows gère son propre Cygwin interne. setup-ocaml v3 : `windows-compiler: mingw|msvc`, pas de Windows ARM. DkML est abandonné (EOL 2026-12-31) : ne pas s'en servir.
- **Nix** : nixpkgs n'a que `haxe_4_3` (4.3.7), sans les deps de development. `pkgsCross.mingwW64` pour OCaml casse régulièrement. Un Mac ne produit pas de binaires Linux sans builder Linux. Non retenu.
- **Apple `container`** (1.0 depuis 2026-06) et OrbStack font la même chose que Docker Desktop. On reste sur Docker Desktop pour la cohérence avec loreline-writer.

Évaluation :

| Cible | Méthode retenue | Fragilité |
|---|---|---|
| Linux x64/arm64 (CI) | Alpine en conteneur sur `ubuntu-24.04` / `ubuntu-24.04-arm`, binaire statique | Faible |
| Linux depuis Mac | Même image via Docker Desktop (arm64 natif, amd64 via Rosetta) | Faible |
| macOS arm64 | Natif | Faible |
| macOS x86_64 | Rosetta (opam x86_64), puis cross-compilateur 5.4+ quand Rosetta ne suffira plus | Moyenne, en hausse |
| Windows (CI) | setup-ocaml mingw, libs C compilées en statique | Moyenne (Cygwin, d'où les retries) |
| Windows depuis Mac | opam-cross-windows ou 5.4 `--target` + llvm-mingw, ~10 paquets à porter, luv à contourner | Élevée, personne ne l'a fait pour Haxe |

## 3. Architecture du projet

```
build-haxe/
  README.md
  PLAN.md                     # ce fichier
  LICENSE
  Brewfile                    # outils hôte seulement : cmake, ninja, pkgconf
  versions.env                # versions et sha256 : opam, zlib, pcre2, mbedtls 2 et 3, neko, images, commit opam-repository
  profiles/
    haxe5/profile.env         # OCaml 5.3.0, mbedtls 3, style de build dune --profile release
    haxe5/haxe.opam.locked
    haxe43/profile.env        # OCaml 5.3.0 (repli 4.14.2), mbedtls 2, dune-workspace.dev
    haxe43/haxe.opam.locked
    haxe43/patches/windows-pcre2-static.patch
  scripts/
    build-neko.sh             # neko depuis les sources, dépendances statiques -> build/neko/<source>/<cible>/
    common.sh                 # détection hôte, profils, chemins, téléchargement vérifié, environnement isolé
    check-host.sh
    detect-profile.sh
    fetch-opam.sh
    build-deps.sh             # zlib, pcre2, mbedtls statiques -> build/deps/<profil>/<cible>/
    setup-switch.sh           # OPAMROOT local, snapshot opam-repository, switch, deps verrouillées
    update-locks.sh
    build-core.sh             # haxe (dune direct, DUNE_BUILD_DIR par cible)
    build-haxelib.sh          # run.n -> nekotools boot -> haxelib
    assemble.sh               # dossier final, signature mac
    verify-binary.sh
    package.sh                # archives, option --ceramic-layout
  setup-haxe.sh
  build-haxe-mac.sh           # arm64 | x86_64 | universal [--from-stages]
  build-haxe-linux.sh         # x64 | arm64, toujours via Docker
  build-haxe-windows.sh       # bash Cygwin de setup-ocaml
  build-haxe-all.sh
  test-haxe.sh
  clean-haxe.sh
  docker/linux.Dockerfile       # Alpine : haxe statique
  docker/linux-glibc.Dockerfile # glibc (Debian 11 x64, Ubuntu 22.04 arm64) : haxelib, assemblage, vérifications
  docker/linux-test.Dockerfile  # image glibc + node, python3, JDK pour les tests
  .github/workflows/build-haxe.yml
```

Gitignorés : `haxe/` (le clone), `.cache/` (opam, OPAMROOT par profil et cible, téléchargements, haxelib), `build/`.

### Variables d'entrée

| Variable | Défaut | Rôle |
|---|---|---|
| `HAXE_REPO` | `https://github.com/HaxeFoundation/haxe.git` | dépôt à cloner |
| `HAXE_BRANCH` | `development` | branche |
| `HAXE_COMMIT` | vide | commit exact (prioritaire sur la branche) |
| `HAXE_PROFILE` | auto | `haxe5` ou `haxe43` |
| `OCAML_VERSION` | du profil | version du compilateur dans le switch |
| `RUN_TESTS` / `TEST_TARGETS` | `0` / `macro,neko` | tests après build |

Exemple fork : `HAXE_REPO=git@github.com:jeremyfa/haxe.git HAXE_BRANCH=new_csharp ./build-haxe-mac.sh`.

### Leviers de reproductibilité

1. **opam isolé** : binaire opam épinglé (release GitHub, sha256 vérifié), `OPAMROOT=.cache/opam/<profil>-<cible>`, jamais `~/.opam`. `OPAMYES=1`, `OPAMCOLOR=never`.
2. **opam-repository figé** : `opam repository add pinned "git+https://github.com/ocaml/opam-repository#<commit>"` puis `opam install ./haxe --deps-only --locked --assume-depexts` avec `haxe.opam.locked` copié dans le clone. Le lock est généré une fois par profil (`opam lock`) et versionné. Un `update-locks.sh` le régénère.
3. **Libs C depuis les sources** : tarballs épinglés avec sha256, CMake (`-DBUILD_SHARED_LIBS=OFF`), préfixe `build/deps/<profil>/<cible>/`. Lien via des `.a` en chemin absolu dans `LIB_PARAMS`. `C_INCLUDE_PATH` et `LIBRARY_PATH` pointent uniquement vers ce préfixe et vers le neko local pendant le build.
4. **Brew limité aux outils** : `Brewfile`, `HOMEBREW_NO_AUTO_UPDATE=1`, `check-host.sh` vérifie les versions minimales. Aucune lib brew dans les chemins de recherche.
5. **Image Linux** : `alpine:3.22@sha256:...`, `apk add` avec liste fixe (build-base, cmake, ninja, git, bash, curl, linux-headers, zstd-static si nécessaire, gmp-dev pour mccs...).
6. **Neko** : releases GitHub `HaxeFoundation/neko` `v2-4-1`, assets disponibles : `linux64`, `linux-arm64`, `osx64`, `osx-arm64`, `osx-universal`, `win64`. sha256 dans `versions.env`.
7. **Clone épinglé** : `.haxe_commit` écrit après checkout, `commit.txt` dans la sortie.

## 4. Détail par cible

### macOS (local et CI `macos-latest`)
- arm64 : natif, `MACOSX_DEPLOYMENT_TARGET=11.0`.
- x86_64 : opam `x86_64-macos` lancé sous Rosetta ; tout le pipeline (deps, switch, make) sous `arch -x86_64`, `MACOSX_DEPLOYMENT_TARGET=10.13`. Deps avec `-DCMAKE_OSX_ARCHITECTURES=x86_64`.
  - Limite : casse avec les Command Line Tools 27. À documenter dans le README. Plan B : cross-compilateur OCaml >= 5.4 `--target x86_64-apple-darwin` (phase future).
- `universal` : `lipo -create` sur `haxe` et `haxelib`, vérification `lipo -archs`.
- `LIB_PARAMS` : les cinq `.a` plus, pour le profil haxe43, `-cclib '-framework Security -framework CoreFoundation'`.
- haxelib : `HAXELIB_LDFLAGS="-Wl,-rpath,@executable_path/../neko"`, neko copié dans `neko/` à côté. Signature ad hoc (`codesign -s -`) au minimum.

### Linux x64 / arm64 (local via Docker Desktop, CI natif)
- `build-haxe-linux.sh` reprend la logique Docker Desktop de `loreline-writer/export-linux.sh` : démarrage, attente, `docker build --platform linux/<amd64|arm64> -f docker/linux.Dockerfile`, `docker run --rm --platform ... -v "$PWD:/workspace"` avec volumes nommés `build-haxe-opam-<arch>` et `build-haxe-deps-<arch>`. Si le script détecte qu'il tourne déjà dans le conteneur (`/.dockerenv` ou variable), il exécute le build directement.
- Mac : arm64 natif, amd64 via Rosetta de Docker Desktop (réglage "Use Rosetta for x86_64/amd64 emulation", vérifié par `check-host.sh`).
- CI : `ubuntu-24.04` et `ubuntu-24.04-arm` lancent le même Dockerfile avec l'arch native.
- Dans Alpine, gcc est musl : pas besoin de `ocaml-option-musl`. `LIB_PARAMS` = `.a` + `-cclib -static`. Vérifier que le switch OCaml ne tire pas zstd dynamiquement (sinon `zstd-static` ou `ocaml-option-no-compression`).
- haxelib : neko n'est pas statique. haxelib reste lié à `libneko.so` avec `-Wl,-rpath,'$ORIGIN/../neko'` et neko copié dans `neko/`. Seul `haxe` est 100 % statique. Vérifier que le neko `linux64` officiel (glibc) tourne bien hors Alpine : les tests haxelib se font sur `debian` et `ubuntu`, pas dans Alpine.

### Windows x64 (CI `windows-2025`)
- `ocaml/setup-ocaml@<sha épinglé>`, `ocaml-compiler: <OCAML_VERSION>`, mingw, `opam-repositories` pointant sur le commit épinglé.
- zlib, pcre2, mbedtls compilés depuis les sources avec le gcc mingw de l'environnement opam, en statique, préfixe `build/deps/...`. Remplace le tarball `Simn/mingw64-mbedtls` et `cygcheck`.
- `LIB_PARAMS` = `.a` + `-cclib -lcrypt32 -cclib -static-libgcc` (+ winpthread statique si nécessaire). Cible : `haxe.exe` sans DLL tierce (`objdump -p | grep "DLL Name"` ne montre que des DLL système).
- Retry sur l'étape opam, `OPAMEXTERNALSOLVER: builtin-mccs+glpk`, comme l'officiel.
- haxelib : `nekotools boot run.n` avec neko `win64` épinglé, `neko.dll` et ndll copiés dans `neko/`.

### Windows depuis le Mac (phase 3, expérimentale)
1. Cross-compilateur OCaml 5.4+ `--target=x86_64-w64-mingw32` avec llvm-mingw (release macOS universelle épinglée) ou mingw-w64 via brew.
2. Deps OCaml vendorées avec opam-monorepo, `dune build -x windows`, ou paquets `-windows` ajoutés à opam-cross-windows.
3. luv : réutiliser `luv_c_generated_types.ml` produit par le job Windows du CI (artefact versionné dans `profiles/<p>/windows/`), au lieu d'exécuter le générateur.
4. haxelib : `nekotools boot` sous wine avec le `neko.exe` win64, ou récupérer `haxelib.exe` du CI. À valider.
5. Critère : le `haxe.exe` cross passe `test-haxe.sh macro` sur le runner Windows. Si l'effort explose, on arrête et Windows reste sur le CI.

## 5. Sortie

```
build/<profil>/<plateforme>-<arch>/haxe/
  haxe[.exe]  haxelib[.exe]  std/  neko/  commit.txt  build_info.txt
build/archives/
  haxe-<profil>-<short>-mac-universal.zip
  haxe-<profil>-<short>-linux-x64.tar.gz
  haxe-<profil>-<short>-linux-arm64.tar.gz
  haxe-<profil>-<short>-windows-x64.zip
```

Compatible avec `ceramic/git/haxe-binary` (`mac/`, `linux-x86_64/`, `linux-arm64/`, `windows/`). Une option `--ceramic-layout` pourra être ajoutée.

## 6. Tests

`test-haxe.sh <plateforme> [default|all|<cibles>]` lance les tests de Haxe (`tests/RunCi.hxml`) sur un dossier construit. `all` prend la liste complète du profil (`FULL_TEST_TARGETS`), moins les cibles exclues sur la plateforme (`TEST_SKIP_*`), comme sur le CI officiel de chaque branche (sans flash). `test-haxe-all.sh` enchaîne mac universel, Linux arm64 et Linux x64. Le détail utilisateur est dans le README (« Running tests »).

Principes (décidés le 2026-11-04) :
- **Tout est figé** dans `test-versions.env` (et les profils pour 4.3) : archives d'outils avec sha256 (Python, PyPy, Node.js, JDK 21 et JDK 11 pour 4.3, PHP, hererocks, paquets npm de deasync) et commits des dépôts (utest, haxeserver, tink_core, hxcoro, hxjava, hxnodejs, format, java-lib-tests, hxcpp, hashlink, hxcs), sha256 de leur tar. Tout est publié dans la release `test-deps` du miroir.
- **RunCi n'installe rien lui-même** : les outils sont pré-installés dans `.cache/test-tools/<plateforme>/`, les bibliothèques haxelib par `haxelib dev`, et les `git clone` / `haxelib git` de RunCi sont redirigés vers des miroirs git locaux des commits figés (`insteadOf` dans le `.gitconfig` du HOME de test).
- **Une exécution RunCi par cible**, dans une copie fraîche des sources, avec `HOME` dans le cache, `TZ=UTC`, une locale UTF-8, et sans `GITHUB_ACTIONS` (sinon RunCi réinstalle depuis les branches par défaut, appelle `sudo apt-get`/`brew`, et lance un echo server par cible sans l'arrêter, ce qui faisait échouer `TestHttp` en enchaînant les cibles). Conséquence : les tests `#if github` ne tournent pas.
- **CI** : un job par build, plateforme et cible (34 pour haxe5, 37 pour haxe43), sur l'archive du job de build (`scripts/test/import-build.sh`, matrice `scripts/test/test-matrix.sh`). La release n'est publiée que si tous passent.

Constats qui ont guidé les choix :
- Haxe 4.3 ne lit pas les `.class` des JDK récents (« Class reader failed: Invalid constant index 0 ») : JDK 11 pour haxe43, comme les runners du CI officiel de 4.3.
- npm 11 ne lance plus les scripts d'installation : `tool-deasync.sh` lance `build.js` de deasync lui-même (binaire précompilé s'il existe, sinon node-gyp avec les en-têtes du node figé ; Linux arm64 compile).
- RunCi 4.3 lance toujours `pip install --user hererocks` sous Linux : `PIP_NO_INDEX` et `PIP_FIND_LINKS` lui font installer la wheel figée.
- HashLink n'a pas de VM sur arm64 : `--skip-hl-jit` et un `hl` factice qui le signale ; la VM 1.x de 4.3 est x86_64 seulement, d'où l'exclusion de `hl` sur mac pour 4.3.

Windows (runners GitHub) : le build passe dans le Cygwin d'opam, les tests dans Git Bash. Les outils natifs (opam, objdump, haxelib.exe, node, git) reçoivent des chemins `D:/a/...` (`cygpath -m`) ; opam y installe lui-même les dépendances système ; Strawberry Perl est retiré du PATH (son `patch.exe` plante, son perl n'a pas les modules de camlp5) et les patches passent par `git apply` ; flexlink reçoit `-link -static` ; le générateur Visual Studio de neko vient de `vswhere` (2026 sur les runners actuels).

Reste non figé : les sources que hererocks et LuaRocks téléchargent pour Lua, les bibliothèques que les tests de tink_core installent depuis lib.haxe.org, et sur mac les bibliothèques C des rocks Lua et mono (Homebrew, `Brewfile.tests`). Pas encore fait sous Windows : `hl` (HashLink avec MSVC) et `lua` (msys2).

## 7. CI : `.github/workflows/build-haxe.yml`

Calqué sur `build-sdl3/.github/workflows/build-sdl3.yml` :
- Déclencheurs : `workflow_dispatch` (inputs `repo`, `ref`, `profile`, `run_tests`), cron quotidien sur `development` et `4.3_bugfix`, push sur les scripts.
- Job `resolve` : résout le commit (`git ls-remote`), saute si la release `haxe-<profil>-<short>` existe.
- Matrice qui appelle **les mêmes scripts** qu'en local : mac arm64 et mac x86_64 (`macos-latest`), linux x64 (`ubuntu-24.04`), linux arm64 (`ubuntu-24.04-arm`), windows x64 (`windows-2025`).
- Job `mac-universal` : télécharge les deux artefacts, `lipo`, `verify-binary.sh`.
- Job tests : `macro,neko` sur chaque plateforme native ; autres cibles en option.
- Job `publish-release` : `gh release create "haxe-<profil>-<short>" --title "Haxe <profil> <date> (<short>)"`, assets renommés comme en 5, `commit.txt` à part.
- Caches : `~/.opam` ou `.cache/opam` keyés sur le hash du lock + `versions.env`.

## 8. Phases d'exécution

### Phase 1 : squelette et macOS
1. `scripts/common.sh`, `versions.env`, `Brewfile`, `check-host.sh`, `.gitignore`, `LICENSE`, `README.md`.
2. `setup-haxe.sh` (clone, submodules `extra/haxelib_src`, `.haxe_commit`), `detect-profile.sh`.
3. `fetch-opam.sh`, `fetch-neko.sh`, `build-deps.sh` (mbedtls 3.6.x pour haxe5, 2.28.x pour haxe43 ; pcre2 10.45 ; zlib 1.3.1).
4. `setup-switch.sh` et génération des deux `haxe.opam.locked` (première exécution sans `--locked`, puis `opam lock`).
5. `build-core.sh`, `build-haxe-mac.sh` arm64, puis x86_64 sous Rosetta, puis universal.
6. `verify-binary.sh`, `test-haxe.sh macro,neko`, pour les deux profils.

### Phase 2 : Linux Docker et CI complet
1. `docker/linux.Dockerfile`, `build-haxe-linux.sh` (logique Docker Desktop de loreline-writer), arm64 puis amd64.
2. `build-haxe-all.sh`, `package.sh`.
3. `build-haxe-windows.ps1` et le workflow GitHub, avec les retries opam.
4. Tests `macro,neko` sur chaque plateforme dans le CI.

### Phase 3 : Windows cross depuis le Mac (expérimental)
Voir section 4. Démarrer par un `ocaml-cross` minimal (hello world OCaml -> `.exe` testé sous wine), puis mesurer l'effort avant d'aller plus loin.

## 9. Vérification

- `verify-binary.sh` :
  - mac : `otool -L` ne liste que `/usr/lib/libSystem` et `/System/Library/Frameworks` ; `vtool -show-build` donne un minos de 11.0 (arm64) ou 10.13 (x86_64) ; `lipo -archs` donne `x86_64 arm64` pour universal.
  - linux : `file haxe` dit "statically linked" ; `haxe --version` passe dans `alpine`, `debian:bullseye` et `ubuntu:20.04` nus ; `haxelib version` passe dans `debian:bullseye` avec le neko embarqué.
  - windows : `objdump -p haxe.exe | grep "DLL Name"` ne montre que `KERNEL32`, `msvcrt`, `ADVAPI32`, `WS2_32`, `CRYPT32`, etc.
- Pour chaque profil : `haxe --version` donne 4.3.x ou 5.0.0-alpha ; `haxelib version` fonctionne ; `test-haxe.sh macro,neko` passe.
- Reproductibilité : deux builds depuis un `.cache` vide donnent un `opam list` identique au lock ; le build réussit sans `/usr/local/lib/neko` ni `/opt/homebrew/opt/{pcre2,mbedtls@3,zlib}` dans les chemins (vérifier que `C_INCLUDE_PATH` / `LIBRARY_PATH` ne contiennent que `build/deps` et `.cache/neko`).
- Fork : `HAXE_REPO=git@github.com:jeremyfa/haxe.git HAXE_BRANCH=new_csharp ./build-haxe-mac.sh` produit un binaire équivalent.

## 10. Points à vérifier au premier passage

- Haxe 4.3.7 sur OCaml 5.3.0 avec `camlp5` 8.03.x : le CI officiel Linux le faisait, donc attendu OK. Sinon repli OCaml 4.14.2 avec `camlp5 = 8.03.04` et `ocamlfind = 1.9.1`.
- Sur Alpine, les paquets opam `domainslib`, `saturn`, `luv` et `ctypes` compilent-ils sans surprise. Le solveur opam par défaut (`builtin-0install`) ne nécessite pas glpk.
- Dépendance zstd du runtime OCaml 5.3 en lien statique.
- Taille et temps du build amd64 sous Rosetta (plus lent qu'en natif, mais bien plus rapide que qemu-user).
- Windows : `-static-libgcc` suffit-il pour supprimer `libgcc_s_seh-1.dll` et `libwinpthread-1.dll` du résultat.
- neko `linux64` officiel : vérifier la version minimale de glibc qu'il exige.

## 11. Références

- Workflows officiels : `https://raw.githubusercontent.com/HaxeFoundation/haxe/development/.github/workflows/main.yml` et `.../4.3_bugfix/.github/workflows/main.yml`
- `extra/BUILDING.md` sur la branche development
- Releases neko : `https://github.com/HaxeFoundation/neko/releases/tag/v2-4-1`
- Releases opam : `https://github.com/ocaml/opam/releases` (binaires `opam-2.3.0-{arm64,x86_64}-macos`, `-linux`)
- Processus de release opam (modèle Alpine + Rosetta) : `https://github.com/ocaml/opam/tree/master/release`
- OCaml 5.4 cross : `https://ocaml.org/releases/5.4.0`, PR `https://github.com/ocaml/ocaml/pull/13526`
- opam-cross-windows : `https://github.com/ocaml-cross/opam-cross-windows`
- dune cross : `https://dune.readthedocs.io/en/latest/cross-compilation.html`
- llvm-mingw : `https://github.com/mstorsjo/llvm-mingw`
- luv générateur ctypes : `https://github.com/aantron/luv/blob/master/src/c/dune`
- Static OCaml musl : `https://soap.coffee/~lthms/posts/OCamlStaticBinaries.html`
- setup-ocaml : `https://github.com/ocaml/setup-ocaml`
- Modèles locaux : `../build-sdl3`, `../build-angle`, `../loreline-writer/export-linux.sh`, `../ceramic/git/haxe-binary`
