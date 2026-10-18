#!/bin/bash
# Run the game headless for N frames and report script errors.
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
FRAMES=${1:-120}
cd "$(dirname "$0")/.."
timeout 300 "$GODOT" --headless --path . --quit-after $FRAMES "${@:2}" > tools/extracted/run.log 2>&1
echo "exit=$?"
grep -A2 -E "SCRIPT ERROR|^ERROR|USER ERROR" tools/extracted/run.log | grep -E "ERROR|at:" | paste - - | sed 's/SCRIPT ERROR: //' | sort | uniq -c | sort -rn | head -${MAXL:-40}
