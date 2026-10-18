# ARAM: Mayhem

A single-player recreation of League of Legends' **ARAM on the Howling Abyss**, built in **Godot 4.7 (GDScript)**:
one human player and nine bots, 14 champions, classic ARAM rules.

The goal is parity with live League. Gameplay values, effects, animations, HUD layout and sounds come from League's
own game data, which `tools/lol` reads from a local install. Custom runtimes then interpret that data in Godot.
Little of it is hand-authored.

> Personal, non-commercial project. League of Legends and all of its assets are property of Riot Games. No game
> assets are stored in this repository: `assets/` is generated locally from your own League installation.

## What's in it

| Area | Summary |
| --- | --- |
| **Match** | Howling Abyss map with lightmapped geometry and a baked floor-height grid. Minion waves on ARAM timing, turrets, inhibitors, nexus, health relics, hexgates, passive gold, fog of war, death/respawn. |
| **Champions** | 14 kits (Ahri, Annie, Darius, Ezreal, Garen, Jinx, Leona, Lux, Malphite, Master Yi, Miss Fortune, Sona, Veigar, Yasuo) on a shared kit framework (missiles, buffs, summons, CC). Also summoner spells, items and the shop. |
| **Bots** | Team AI (engage, hold, retreat, focus fire), orb-walking, skillshot dodging, personas (aggression, caution, wander, emotes) and hexgate use. |
| **VFX runtime** | League `VfxSystemDefinitionData` (bins → JSON) played by a custom particle runtime. Covers emitters, probability tables, fields, meshes, trails, distortion, palettes and erosion, with League's gamma-space blending. |
| **Motion** | League `AnimationGraphData` driver: clip selection, blend and transition clips, data-timed attack and spell release, bone sockets, animation events. |
| **UI** | HUD, shop and scoreboard laid out from League's UI bins and atlases. World UI (health bars, floating text, cursors, indicators), menus, champion select, loading screen, end of game. |
| **Audio** | League SFX, VO, announcer, ambience and music through a pooled 3D audio router. UI sounds from the League client. |

## Running

1. Install Godot 4.7 (the `godot.windows.opt.tools.64.exe` binary).
2. Generate `assets/` from your League install with the extractors in `tools/lol` (see below). The game expects
   League at `D:\Riot Games\League of Legends`. There is no single extract-all script yet; each extractor's
   docstring lists what it writes.
3. Run `Play ARAM Mayhem.bat`, or `godot --path .`

Useful command-line arguments (after `--`):

| Argument | Effect |
| --- | --- |
| `--champ=Ezreal` | Pick the player's champion. |
| `--sim --botplayer --time=600 --seed=1` | Play a full match automatically, headless or windowed. |
| `--res=2560x1440 --novsync` | Window size, with vsync off. |
| `--shots=60,90 --shotdir=NAME` | Save screenshots at match times (in seconds). |
| `--harness=res://src/debug/perf_probe.gd` | Attach a debug or test harness to the match. |
| `--linear` | Use Godot's default linear blending instead of League's gamma-space pipeline (A/B testing). |

## Repository layout

| Path | Contents |
| --- | --- |
| `src/core` | Units, champions, minions, turrets, combat, buffs, missiles, navigation, animation graph. |
| `src/champions` | Kit framework and per-champion kits. |
| `src/ai` | Bot brain and team AI. |
| `src/match` | Match loop, rules, wave spawner, map builder. |
| `src/vfx` | League VFX runtime (`lol_vfx.gd`, particle shaders) and character/map shaders. |
| `src/render` | Colour pipeline (gamma-space blending compositor effect). |
| `src/ui` | HUD, shop, scoreboard, menus, world UI. |
| `src/audio`, `src/autoload` | Audio router and global singletons. |
| `src/debug` | Test and profiling harnesses: kit tests, VFX viewer, perf probe, A/B tools. |
| `data/` | Extracted, structured game data: champion stats, VFX systems, animation graphs, map layout, audio events. |
| `tools/lol` | League file parsers and extractors: WAD, bin, tex, skn/skl/anm, mapgeo, shaders, audio. |
| `tools/*.sh` | Headless checks, silent off-screen previews, long simulations, full release regression (`final_check.sh`). |
| `docs/` | Format notes, fidelity gaps, QA findings, League shader analysis, agent briefing. |

## Testing

- `tools/final_check.sh` is the release regression. It runs:
  - every champion's ability test;
  - three 10-minute simulated matches;
  - a 2560×1440 performance run with screenshots.
- `tools/check.sh <frames> -- <args>` is a quick headless script-error check.
- `tools/preview.sh <timeout> -- <args>` renders runs silently and off-screen, for screenshots and VFX inspection.
