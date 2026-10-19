#!/bin/bash
# [vfx-leak] kit tests (all abilities, all 14 champions) with the lingering-effect detector as a second harness.
#   tools/leak_kits.sh   -> tools/extracted/leak/kit_<Champ>.log + one summary
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
mkdir -p tools/extracted/leak
for c in Ahri Annie Darius Ezreal Garen Jinx Leona; do
  (timeout 500 "$GODOT" --headless --path . --fixed-fps 60 -- --champ=$c --harness=res://src/debug/kit_test_a.gd --harness=res://src/debug/vfx_leak_probe.gd --leak_age=6 > tools/extracted/leak/kit_$c.log 2>&1) &
done
wait
for c in Lux Malphite MasterYi MissFortune Sona Veigar Yasuo; do
  (timeout 500 "$GODOT" --headless --path . --fixed-fps 60 -- --champ=$c --harness=res://src/debug/kit_test_b.gd --harness=res://src/debug/vfx_leak_probe.gd --leak_age=6 > tools/extracted/leak/kit_$c.log 2>&1) &
done
wait
for f in tools/extracted/leak/kit_*.log; do
  echo "== $(basename $f .log): $(grep -hE 'KITB? DONE' $f | tail -1 | cut -c1-70) script_errors=$(grep -c 'SCRIPT ERROR' $f)"
  grep -E "LEAKRPT  [A-Z_]+ +n=" $f | cut -c1-210
done
