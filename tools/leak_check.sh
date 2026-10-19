#!/bin/bash
# [vfx-leak] three 600 s sims with the lingering-effect detector (src/debug/vfx_leak_probe.gd).
#   tools/leak_check.sh [time] [seeds...]   -> tools/extracted/leak/sim_<seed>.log, summary on stdout
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
T=${1:-600}; shift
SEEDS=${@:-11 22 33}
mkdir -p tools/extracted/leak
for s in $SEEDS; do
  (timeout 1800 "$GODOT" --headless --path . --fixed-fps 60 -- --sim --time=$T --seed=$s --harness=res://src/debug/vfx_leak_probe.gd --leak_every=300 > tools/extracted/leak/sim_$s.log 2>&1; echo "EXIT $?" >> tools/extracted/leak/sim_$s.log) &
done
wait
for s in $SEEDS; do
  L=tools/extracted/leak/sim_$s.log
  echo "== seed $s: $(grep -E '^EXIT' $L) script_errors=$(grep -c 'SCRIPT ERROR' $L) $(grep -E 'GAME OVER' $L | head -1)"
  awk '/LEAKRPT ===== FINAL/{f=1} f&&/LEAKRPT/' $L | head -60
done
