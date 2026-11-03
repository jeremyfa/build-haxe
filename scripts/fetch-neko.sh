#!/usr/bin/env bash
# Download and extract the pinned neko release for a target.
# Usage: scripts/fetch-neko.sh <target>

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:?usage: fetch-neko.sh <target>}"
check_target "$target"

asset="$(neko_asset "$target")"
dest="$(neko_dir "$target")"
stamp="$dest/.version"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$NEKO_VERSION" ]; then
    log "neko $NEKO_VERSION ($asset) already present"
    exit 0
fi

sha_var="NEKO_SHA256_${asset//-/_}"
case "$asset" in
    win64) ext=zip ;;
    *) ext=tar.gz ;;
esac
file="$(download "https://github.com/HaxeFoundation/neko/releases/download/$NEKO_TAG/neko-$NEKO_VERSION-$asset.$ext" "${!sha_var}")"

mkdir -p "$dest"
if [ "$ext" = "zip" ]; then
    unzip -q -o "$file" -d "$dest.extract"
else
    mkdir -p "$dest.extract"
    tar -xzf "$file" -C "$dest.extract"
fi
# Archives contain a single top-level folder: flatten it into $dest.
cp -R "$dest.extract/neko-$NEKO_VERSION-$asset/." "$dest/"
echo "$NEKO_VERSION" > "$stamp"
log "neko $NEKO_VERSION ready: $dest"
