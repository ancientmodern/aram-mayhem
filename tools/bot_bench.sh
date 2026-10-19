#!/bin/bash
# [bot-diff] Bot difficulty benchmark: headless bot-vs-bot matches, level A vs level B, both sides, several seeds.
#   tools/bot_bench.sh [-p "3:0 2:1 ..."] [-s "1 2 3 4"] [-t 900] [-j 8] [-o tag] [-x "extra game args"]
#   -p  pairings A:B (A, B = difficulty 0..3; every pairing is played with A on ORDER and on CHAOS for each seed)
#   -s  seeds   -t  game-time cap per match in seconds (undecided matches are adjudicated: kills + structures, turret 3 / inhibitor 6)
#   -j  parallel matches (each Godot ~2 GB RAM)   -o  tag for the log folder (tools/extracted/botdiff/<tag>)
#   -x  extra game args for every match, e.g. "--botlv=3:kite=0.5" (overrides a BotBrain.LV entry for tuning / ablations)
# Output: BENCH lines in the logs + the summary table from tools/bot_bench_report.py.
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
PAIRS="3:0 2:0 1:0 3:1 2:1 3:2 3:3"
SEEDS="1 2 3 4 5 6"
CAP=900
JOBS=8
TAG=bench
EXTRA=""
while getopts "p:s:t:j:o:x:" o; do
  case $o in p) PAIRS=$OPTARG;; s) SEEDS=$OPTARG;; t) CAP=$OPTARG;; j) JOBS=$OPTARG;; o) TAG=$OPTARG;; x) EXTRA=$OPTARG;; *) exit 1;; esac
done
cd "$(dirname "$0")/.."
OUT=tools/extracted/botdiff/$TAG
rm -rf "$OUT"; mkdir -p "$OUT"
timeout 300 "$GODOT" --headless --path . --import > "$OUT/import.log" 2>&1
grep -A2 "SCRIPT ERROR" "$OUT/import.log" | head -20
JOBLIST="$OUT/jobs.txt"; : > "$JOBLIST"
for p in $PAIRS; do
  A=${p%%:*}; B=${p##*:}
  for s in $SEEDS; do
    echo "$A $B $s" >> "$JOBLIST"                         # first number = ORDER level, second = CHAOS level
    [ "$A" != "$B" ] && echo "$B $A $s" >> "$JOBLIST"    # swapped sides
  done
done
run_one() {
  read -r O C S <<< "$1"
  timeout $((CAP * 3 + 300)) "$GODOT" --headless --path . --fixed-fps 60 -- --sim --time=$CAP --seed=$S --botlevels=$O,$C $EXTRA \
      --harness=res://src/debug/bot_bench.gd > "$OUT/m_${O}v${C}_s${S}.log" 2>&1
}
export -f run_one; export GODOT CAP OUT EXTRA
xargs -P "$JOBS" -I{} bash -c 'run_one "{}"' < "$JOBLIST"
python tools/bot_bench_report.py "$OUT"
