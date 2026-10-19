#!/bin/bash
# [timing] Headless timing check for all 14 champions (cast times, missile speeds, attack windups vs the League bins).
#   tools/timing_check.sh [Champ ...]  -> logs in tools/extracted/timing/<Champ>.log, summary on stdout
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
OUT=tools/extracted/timing
mkdir -p $OUT
CH=("$@"); [ ${#CH[@]} -eq 0 ] && CH=(Ahri Annie Darius Ezreal Garen Jinx Leona Lux Malphite MasterYi MissFortune Sona Veigar Yasuo)
i=0
for c in "${CH[@]}"; do
  (timeout 300 "$GODOT" --headless --path . --fixed-fps 60 -- --champ=$c --harness=res://src/debug/timing_test.gd > $OUT/$c.log 2>&1) &
  i=$((i+1)); [ $((i % 4)) -eq 0 ] && wait
done
wait
for c in "${CH[@]}"; do
  L=$OUT/$c.log
  echo "$c: $(grep -h 'TIMING DONE' $L | tail -1) script_errors=$(grep -c 'SCRIPT ERROR' $L)"
  grep -h 'TIMING FAIL' $L
done
