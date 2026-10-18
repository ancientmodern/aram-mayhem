#!/bin/bash
# Run several seeded headless sims in parallel. Usage: tools/multisim.sh <seconds> <seed> [seed...]
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
T=$1; shift
timeout 300 "$GODOT" --headless --path . --import > tools/extracted/import.log 2>&1
grep -A2 "SCRIPT ERROR" tools/extracted/import.log | grep -E "ERROR|at:" | paste - - | sed 's/SCRIPT ERROR: //' | sort -u | head -30
for s in "$@"; do
  (timeout $((T * 2 + 120)) "$GODOT" --headless --path . --fixed-fps 60 -- --sim --time=$T --seed=$s > tools/extracted/sim_s$s.log 2>&1; echo "EXIT $?" >> tools/extracted/sim_s$s.log) &
done
wait
for s in "$@"; do
  L=tools/extracted/sim_s$s.log
  echo "=== seed $s: $(grep -E '^EXIT' $L) last=$(grep -E '^\[' $L | tail -1 | cut -c1-8) $(grep -E 'WATCHDOG|GAME OVER' $L | head -2 | tr '\n' ' ')"
  grep -A2 -E "SCRIPT ERROR|^ERROR|WARNING: (Missile|Non-finite)" $L | grep -E "ERROR|WARNING|at:" | grep -v "leaked\|BUG: Unreferenced\|PagedAllocator" | paste - - | sed 's/SCRIPT ERROR: //' | sort | uniq -c | sort -rn | head -12
done
