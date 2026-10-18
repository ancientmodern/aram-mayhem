#!/bin/bash
# Run a Godot preview/test (vfxtest, uitest, windowed sims) WITHOUT disturbing the desktop:
#  - at most PREVIEW_SLOTS (default 3) previews run at once across all agents (slot locks in tools/extracted/)
#    3 fits this machine: each windowed instance takes ~1.7 GB RAM; the GPU cost per frame is ~1-2 ms
#  - perf measurements run EXCLUSIVELY (no other preview at the same time, or fps numbers are meaningless):
#    automatic when the args mention perf_probe, or force it with PREVIEW_EXCLUSIVE=1
#  - the window is small, placed off-screen and never takes focus
# Usage: tools/preview.sh <timeout_seconds> -- <game args after "--">
#   e.g. tools/preview.sh 150 -- --champ=Lux --vfxtest=Lux_Base_Q_mis --vfxdir=vfx_lux
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
T=${1:-150}; shift
[ "$1" = "--" ] && shift
N=${PREVIEW_SLOTS:-3}
D=tools/extracted
mkdir -p "$D"
EXCL=${PREVIEW_EXCLUSIVE:-0}
case "$*" in *perf_probe*) EXCL=1 ;; esac
now() { date +%s; }
# a slot is stale when its owner's deadline (start + timeout + 60 s) has passed
clear_stale() {
  local s=$1
  if [ -d "$s" ]; then
    local dl; dl=$(cat "$s/deadline" 2>/dev/null || echo 0)
    if [ "$dl" -gt 0 ] && [ "$(now)" -gt "$dl" ]; then rm -rf "$s"; fi
    # slot dir without a deadline file (owner died between mkdir and write) older than 30 s
    if [ ! -f "$s/deadline" ] && [ -n "$(find "$s" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then rm -rf "$s"; fi
  fi
}
take() {  # take slot dir $1, record deadline
  mkdir "$1" 2>/dev/null || return 1
  echo $(( $(now) + T + 60 )) > "$1/deadline"
  return 0
}
HELD=()
release() { for s in "${HELD[@]}"; do rm -rf "$s"; done; [ "$EXCL" = 1 ] && rm -rf "$D/preview.excl_wait"; }
trap release EXIT
if [ "$EXCL" = 1 ]; then
  # announce, so normal previews stop taking free slots, then collect every slot in order
  until mkdir "$D/preview.excl_wait" 2>/dev/null; do clear_stale "$D/preview.excl_wait"; sleep 2; done
  echo $(( $(now) + 3600 )) > "$D/preview.excl_wait/deadline"
  for i in $(seq 0 $((N - 1))); do
    until take "$D/preview.slot$i"; do clear_stale "$D/preview.slot$i"; sleep 2; done
    HELD+=("$D/preview.slot$i")
  done
else
  got=""
  until [ -n "$got" ]; do
    if [ ! -d "$D/preview.excl_wait" ]; then
      for i in $(seq 0 $((N - 1))); do
        clear_stale "$D/preview.slot$i"
        if take "$D/preview.slot$i"; then got="$D/preview.slot$i"; break; fi
      done
    else
      clear_stale "$D/preview.excl_wait"
    fi
    [ -z "$got" ] && sleep 2
  done
  HELD+=("$got")
fi
timeout "$T" "$GODOT" --path . --audio-driver Dummy $GODOT_EXTRA --windowed --position -3000,-3000 --resolution 1280x720 -- --windowed --offscreen "$@"
