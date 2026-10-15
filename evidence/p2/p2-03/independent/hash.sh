#!/bin/bash
cd /c/godot/greenvader
{ echo "{"; first=1
for f in $(find scripts scenes data -type f \( -name '*.gd' -o -name '*.tscn' -o -name '*.tres' -o -name '*.json' -o -name '*.gdshader' \) | sort) project.godot; do
 h=$(sha256sum "$f"|cut -d' ' -f1); [ $first = 0 ] && echo ","; first=0; printf '  "%s": "%s"' "$f" "$h"; done; echo; echo "}"; } > "evidence/p2/p2-03/independent/$1"
