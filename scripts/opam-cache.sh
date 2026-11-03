#!/usr/bin/env bash
# Build the archive of the opam package sources of a profile's lock file.
# Usage: HAXE_PROFILE=<profile> scripts/opam-cache.sh <out.tar.gz>
#
# Uses `opam admin cache` on a copy of the pinned opam-repository snapshot
# reduced to the packages of the lock: every source is downloaded and checked
# against the checksums of the repository, and stored with opam's cache
# layout (md5/, sha256/, sha512/). setup-switch.sh then uses it as
# archive-mirrors, so opam never needs the original hosts.
# The archive has no pinned sha256: opam checks each file it takes from it.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

out="${1:?usage: opam-cache.sh <out.tar.gz>}"
load_profile
[ -f "$PROFILE_LOCK" ] || die "no lock file for $HAXE_PROFILE"

host="$(host_target)"
[ "$HOST_OS" = "windows" ] && die "run opam-cache.sh on macOS or Linux"
"$ROOT/scripts/fetch-opam.sh" "$host" >/dev/null
opam="$(opam_bin "$host")"
snapshot="$(opam_repo_snapshot)"

work="$PRODUCTS_CACHE_DIR/opam-cache-work/$HAXE_PROFILE-$(lock_hash)"
[ ! -e "$work" ] || mv "$work" "$work.old.$(date +%Y%m%d%H%M%S)"
mkdir -p "$work/repo/packages"
cp "$snapshot/repo" "$work/repo/"
[ -f "$snapshot/version" ] && cp "$snapshot/version" "$work/repo/"

# "name" {= "version"} lines of the lock
grep -o '"[^"]*" {= "[^"]*"}' "$PROFILE_LOCK" | sed -E 's/"([^"]*)" \{= "([^"]*)"\}/\1 \2/' |
while read -r name version; do
    pkg="$snapshot/packages/$name/$name.$version"
    [ -d "$pkg" ] || die "$name.$version is not in opam-repository $OPAM_REPO_COMMIT"
    mkdir -p "$work/repo/packages/$name"
    cp -R "$pkg" "$work/repo/packages/$name/"
done

log "downloading the sources of $(ls "$work/repo/packages" | wc -l | tr -d ' ') packages"
(cd "$work/repo" && OPAMYES=1 "$opam" admin cache "$work/opam-cache")

mkdir -p "$(dirname "$out")"
(cd "$work" && tar -czf "$out.part.$$" opam-cache)
mv -f "$out.part.$$" "$out"
log "opam cache: $out ($(du -h "$out" | cut -f1))"
