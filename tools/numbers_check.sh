#!/bin/bash
# [numbers] Headless formula / ARAM-number assertions (src/debug/numbers_test.gd). Prints NUM PASS|FAIL lines and "NUM DONE".
#   tools/numbers_check.sh           -> exit code 1 when any assertion fails
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
OUT=tools/extracted/numbers_test.log
timeout 300 "$GODOT" --headless --path . --fixed-fps 60 -- --champ=Ezreal --harness=res://src/debug/numbers_test.gd > "$OUT" 2>&1
grep -E "^NUM (FAIL|DONE)" "$OUT"
grep -A2 "SCRIPT ERROR" "$OUT" | head -10
! grep -q "^NUM FAIL" "$OUT" && grep -q "^NUM DONE" "$OUT"
