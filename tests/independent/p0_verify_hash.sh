#!/bin/sh
# usage: p0_verify_hash.sh out.json  (SHA-256 of frozen game files)
cd /c/godot/greenvader || exit 1
{
echo '{'
first=1
for f in $(find scripts scenes -type f | sort) project.godot; do
  h=$(sha256sum "$f" | cut -d' ' -f1)
  [ $first = 1 ] || echo ','
  first=0
  printf '  "%s": "%s"' "$f" "$h"
done
echo
echo '}'
} > "$1"
