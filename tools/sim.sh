#!/bin/bash
# Refresh class cache, then run a headless simulation. Usage: tools/sim.sh <seconds> [extra user args]
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
timeout 300 "$GODOT" --headless --path . --import > tools/extracted/import.log 2>&1
grep -A2 "SCRIPT ERROR" tools/extracted/import.log | grep -E "ERROR|at:" | paste - - | sed 's/SCRIPT ERROR: //' | sort -u | head -30
T=${1:-120}
timeout ${TIMEOUT:-400} "$GODOT" --headless --path . --fixed-fps 60 -- --sim --time=$T "${@:2}" > tools/extracted/sim.log 2>&1
echo "sim exit=$?"
grep -A2 -E "SCRIPT ERROR|^ERROR" tools/extracted/sim.log | grep -E "ERROR|at:" | grep -v "leaked\|BUG: Unreferenced\|PagedAllocator" | paste - - | sed 's/SCRIPT ERROR: //' | sort | uniq -c | sort -rn | head -30
grep -E "^\[" tools/extracted/sim.log | head -${MAXL:-80}
