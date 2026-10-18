#!/bin/bash
# Run a Godot preview/test (vfxtest, uitest, windowed sims) WITHOUT disturbing the desktop:
#  - only one preview runs at a time across all agents (lock in tools/extracted/preview.lock)
#  - the window is small, placed off-screen and never takes focus
# Usage: tools/preview.sh <timeout_seconds> -- <game args after "--">
#   e.g. tools/preview.sh 150 -- --champ=Lux --vfxtest=Lux_Base_Q_mis --vfxdir=vfx_lux
GODOT="/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.."
T=${1:-150}; shift
[ "$1" = "--" ] && shift
LOCK=tools/extracted/preview.lock
mkdir -p tools/extracted
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  # stale lock (owner died) after 10 minutes
  if [ $waited -gt 600 ]; then rm -rf "$LOCK"; fi
  sleep 2; waited=$((waited + 2))
done
trap 'rm -rf "$LOCK"' EXIT
timeout "$T" "$GODOT" --path . --audio-driver Dummy --windowed --position -3000,-3000 --resolution 1280x720 -- --windowed --offscreen "$@"
