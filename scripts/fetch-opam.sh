#!/usr/bin/env bash
# Download the pinned opam binary for a target.
# Usage: scripts/fetch-opam.sh <target>

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: fetch-opam.sh <target>}"
check_target "$target"
os="$(target_os "$target")"
arch="$(target_arch "$target")"

case "$os" in
    mac) asset="$arch-macos" ;;
    linux) asset="$arch-linux" ;;
    windows) log "opam is provided by setup-ocaml on Windows"; exit 0 ;;
esac

sha_var="OPAM_SHA256_${asset//-/_}"
file="$(download "https://github.com/ocaml/opam/releases/download/$OPAM_VERSION/opam-$OPAM_VERSION-$asset" "${!sha_var}")"

dest="$(opam_bin "$target")"
mkdir -p "$(dirname "$dest")"
if [ ! -f "$dest" ] || [ "$(sha256_of "$dest")" != "${!sha_var}" ]; then
    replace_file "$file" "$dest"
    chmod +x "$dest"
fi
log "opam $OPAM_VERSION ready: $dest"
