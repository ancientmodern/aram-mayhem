#!/bin/bash
# Full regression for a release candidate. Run from the project root (main tree or the ARAM_lead snapshot).
#   tools/final_check.sh            -> results in tools/extracted/final/*.log and a summary on stdout
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
OUT=tools/extracted/final
rm -rf "$OUT"; mkdir -p "$OUT"
echo "== import"
timeout 400 "$GODOT" --headless --path . --import > $OUT/import.log 2>&1
grep -A2 "SCRIPT ERROR" $OUT/import.log | grep -E "ERROR|at:" | sort -u | head -10
echo "== kit tests (parallel)"
for c in Ahri Annie Darius Ezreal Garen Jinx Leona; do
  (timeout 500 "$GODOT" --headless --path . --fixed-fps 60 -- --champ=$c --harness=res://src/debug/kit_test_a.gd > $OUT/kit_$c.log 2>&1) &
done
wait
for c in Lux Malphite MasterYi MissFortune Sona Veigar Yasuo; do
  (timeout 500 "$GODOT" --headless --path . --fixed-fps 60 -- --champ=$c --harness=res://src/debug/kit_test_b.gd > $OUT/kit_$c.log 2>&1) &
done
wait
for f in $OUT/kit_*.log; do
  echo "$(basename $f .log): $(grep -hE 'KITB? DONE' $f | tail -1 | cut -c1-80) $(grep -hcE 'KITB? FAIL' $f) fails, $(grep -c 'SCRIPT ERROR' $f) script errors"
done
echo "== long sims (600 s x 3)"
for s in 11 22 33; do
  (timeout 1500 "$GODOT" --headless --path . --fixed-fps 60 -- --sim --time=600 --seed=$s > $OUT/sim_$s.log 2>&1; echo "EXIT $?" >> $OUT/sim_$s.log) &
done
wait
for s in 11 22 33; do
  L=$OUT/sim_$s.log
  echo "seed $s: $(grep -E '^EXIT' $L) last=$(grep -E '^\[' $L | tail -1 | cut -c1-8) $(grep -E 'GAME OVER|WATCHDOG' $L | head -2 | tr '\n' ' ') script_errors=$(grep -c 'SCRIPT ERROR' $L)"
  grep -A2 "SCRIPT ERROR" $L | grep -E "ERROR|at:" | paste - - | sed 's/SCRIPT ERROR: //' | sort | uniq -c | sort -rn | head -5
done
echo "== 2K perf + screenshots"
tools/preview.sh 260 -- --sim --botplayer --time=120 --seed=4 --champ=Ezreal --res=2560x1440 --novsync --shots=58,62,66,90,115 --shotdir=final_shots --harness=res://src/debug/perf_probe.gd > $OUT/perf.log 2>&1
grep "^PERF" $OUT/perf.log | cut -c1-75
echo "== done"
