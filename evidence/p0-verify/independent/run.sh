#!/bin/sh
# usage: run.sh <tag> <suite> <mode> <size> [extra]
# Runs the driver in a normal GPU window (Forward+), APPDATA/LOCALAPPDATA isolated to a temp profile.
R=/c/godot/greenvader
O=$R/evidence/p0-verify/independent
WO=C:/godot/greenvader/evidence/p0-verify/independent
export APPDATA="C:\godot\greenvader\evidence\p0-verify\independent\profile\roaming"
export LOCALAPPDATA="C:\godot\greenvader\evidence\p0-verify\independent\profile\local"
/c/godot/Godot_v4.7.2-stable_win64_console.exe --path C:/godot/greenvader --rendering-driver vulkan --rendering-method forward_plus --log-file $WO/$1-godot.log res://tests/independent/p0_verify_driver.tscn -- --suite=$2 --mode=$3 --size=$4 --tag=$1 --out=$WO $5 > $O/$1-stdout.log 2>&1 &

wait $!
echo "exit=$?" >> $O/$1-stdout.log
