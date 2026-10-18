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
# external memory guard: kill any Godot process above 4 GB private memory (protects the pagefile / disk)
powershell -NoProfile -Command "Start-Sleep 5; while (Get-Process godot* -ErrorAction SilentlyContinue) { Get-Process godot* -ErrorAction SilentlyContinue | Where-Object { \$_.PrivateMemorySize64 -gt 4GB } | ForEach-Object { Write-Output ('MEMGUARD killed ' + \$_.Id); Stop-Process -Id \$_.Id -Force }; Start-Sleep 3 }" > tools/extracted/memguard.log 2>&1 &
wait
cat tools/extracted/memguard.log 2>/dev/null
for s in "$@"; do
  L=tools/extracted/sim_s$s.log
  echo "=== seed $s: $(grep -E '^EXIT' $L) last=$(grep -E '^\[' $L | tail -1 | cut -c1-8) $(grep -E 'WATCHDOG|GAME OVER' $L | head -2 | tr '\n' ' ')"
  grep -A2 -E "SCRIPT ERROR|^ERROR|WARNING: (Missile|Non-finite)" $L | grep -E "ERROR|WARNING|at:" | grep -v "leaked\|BUG: Unreferenced\|PagedAllocator" | paste - - | sed 's/SCRIPT ERROR: //' | sort | uniq -c | sort -rn | head -12
done
