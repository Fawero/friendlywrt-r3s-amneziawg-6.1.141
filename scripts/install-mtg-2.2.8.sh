#!/bin/sh
set -eu

VER="2.2.8"
FILE="mtg-${VER}-linux-arm64.tar.gz"
URL="https://github.com/9seconds/mtg/releases/download/v${VER}/${FILE}"
SHA256="562a94dd4cafcb8f179b76cfeafb76da12747c8e230bc76235bf8746cc189644"
WORK="${TMPDIR:-/tmp}/korobka-mtg-${VER}"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

curl -fL "$URL" -o "$FILE"
echo "$SHA256  $FILE" | sha256sum -c -

tar -xzf "$FILE"
MTG_BIN="$(find "$WORK" -type f -name mtg | head -1)"
[ -n "$MTG_BIN" ] && [ -f "$MTG_BIN" ] || {
    echo "MTG binary not found after extraction" >&2
    exit 1
}

mkdir -p /usr/local/bin
cp "$MTG_BIN" /usr/local/bin/mtg
chmod 0755 /usr/local/bin/mtg

/usr/local/bin/mtg --version
