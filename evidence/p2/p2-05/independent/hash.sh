#!/bin/bash
cd /c/godot/greenvader
out="$1"
{
echo "{"
first=1
for f in $(find scripts scenes data project.godot -type f ! -name '*.uid' | sort); do
  h=$(sha256sum "$f" | cut -d' ' -f1)
  [ $first = 1 ] || echo ","
  first=0
  printf '  "%s": "%s"' "$f" "$h"
done
echo; echo "}"
} > "$out"
sha256sum "$out" >/dev/null
