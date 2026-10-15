#!/bin/bash
cd /c/godot/greenvader
H=$(find scripts scenes data -type f ! -name '*.uid' | LC_ALL=C sort | xargs sha256sum project.godot | sha256sum | cut -d' ' -f1)
echo "{\"time\":\"$(date -Iseconds)\",\"sha256_scripts_scenes_data_project\":\"$H\",\"files\":$(find scripts scenes data -type f ! -name '*.uid' | wc -l)}" > evidence/p2/p2-02/independent/$1.json
cat evidence/p2/p2-02/independent/$1.json
