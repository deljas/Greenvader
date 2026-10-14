#!/bin/bash
# usage: hash_sources.sh out.json  -> SHA-256 of scripts/, scenes/, data/, project.godot (excluding .uid/.import caches are included as files too)
cd C:/godot/greenvader
{
 echo "{"
 first=1
 for f in $(find scripts scenes data -type f | sort) project.godot; do
   h=$(sha256sum "$f" | cut -d' ' -f1)
   [ $first -eq 0 ] && echo ","
   first=0
   printf '  "%s": "%s"' "$f" "$h"
 done
 echo; echo "}"
} > "$1"
sha256sum "$1" | cut -d' ' -f1
