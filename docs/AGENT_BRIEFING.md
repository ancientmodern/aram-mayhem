# Agent briefing (read fully before starting)

Project: **D:\Games\ARAM_Mayhem** — Godot 4.7.2 (GDScript) single-player recreation of League of Legends ARAM on the
Howling Abyss: one human plus 9 bots. The player judges everything against live League and rejects anything that
feels like a "rough demo" or a "pile of free assets". The bar is **identical to League, premium polish**.

## Ground truth (never guess)
- **League game files:** `D:\Riot Games\League of Legends\Game`. WADs live under DATA/FINAL: champions, Maps/Shipping/Map12,
  UI.wad.client, DATA.wad.client, Global.wad.client, and Localized/ (fontconfig).
- **League client files:** `D:\Riot Games\League of Legends\Plugins` (rcp-fe-* WADs: client UI art, sounds, fonts).
- **Parsers:** in `tools/lol/` (wad.py, binfile.py, dump_bin.py, tex.py, names.py, extract_vfx.py, extract_hud.py,
  extract_client_audio.py, extract_game_audio.py, extract_map_*.py, export_character.py…). Formats are documented in
  `docs/research/league_formats.md`. Audio decoding uses vgmstream in `tools/vgmstream`.
- **CommunityDragon:** raw.communitydragon.org, plus hash lists at github.com/CommunityDragon/Data. Download them freely.
- **References:** the League wiki (WebFetch), Riot ability videos, and real gameplay screenshots and videos.
- Authentic League assets and data are allowed (personal project).

## Key docs
- `docs/KIT_GUIDE.md`: champion kit API, the LolVfx API (load_set / has / make / spawn / attach, bone sockets via
  `Unit.socket()`), and GameAudio.
- `docs/FIDELITY_GAPS.md`: known gaps.
- `docs/QA_FINDINGS.md`: QA issue list (may not exist yet).

## Running things
- **Godot:** `"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"`.
- **Headless error check:** `tools/check.sh <frames> -- <game args>`. After adding a `class_name`, run Godot once with
  `--headless --path . --import`.
- **Visual runs:** ONLY through `tools/preview.sh <timeout> -- <game args>`. It is serialized, silent and off-screen.
  Never open a Godot window any other way. Never run non-headless Godot without `--audio-driver Dummy`.
- **Useful game args:**
  - `--champ=Ezreal`: player champion.
  - `--sim --botplayer --time=N --seed=N`: auto-played match.
  - `--shots=a,b,c --shotdir=NAME`: screenshots at those match seconds.
  - `--res=2560x1440 --novsync`: perf-realistic resolution.
  - `--harness=res://path.gd`: your own Node script added to the match. It gets `match_ref` and `main` if it declares them.
- **Screenshots:** they land in `%APPDATA%/Godot/app_userdata/ARAM- Mayhem/<shotdir>/`. LOOK at them with the Read tool and
  describe what you see. Work isn't done until you've verified it visually against League references.
- **Existing harnesses:** src/debug/vfx_test.gd (play any VFX system), src/debug/kit_test_a.gd and kit_test_b.gd
  (all abilities; must keep passing), src/ui/hud/hud_test.gd (HUD and shop input), src/debug/control_test.gd (input
  injection), src/debug/ui_test.gd (`--uitest` menu flow), src/debug/perf_probe.gd (frame profiling: PERF lines).
- **Long-running work:** run slow commands in the background and keep working meanwhile.

## Rules
- **Ownership:** edit only the files your brief says you own. If something elsewhere must change, make it minimal, surgical
  and commented with your tag, and list it in your final report. Re-read a file right before editing it, because other
  agents work in parallel.
- **No commits:** don't `git commit`; the lead reviews and commits. Write LF line endings.
- **Partial work:** if a previous agent did part of your task, `git status` / `git diff` show their uncommitted work in your
  files. Review it, keep what's good, and finish it.
- **Performance budget:** 60+ fps, ideally 120, in a 10-champion teamfight at 2560x1440.
  - Never create materials, textures or shaders per event; prebuild at load.
  - No per-node GDScript `_process` for effects.
  - Measure with perf_probe when you touch hot paths.
- **Never iterate a Dictionary keyed by objects directly** (`for u in dict:`). Iterate `dict.keys()` instead. Once a key
  object is freed, its hash changes and direct iteration can loop forever; that caused the long-match freeze.
- **Sound:** UI sounds go through `Sfx.ui_file("res://assets/audio/ui/<area>/<file>.ogg")` (or `Sfx.ui(name)`). In-match
  sounds go through GameAudio (`match.audio`).
- **Final report:** at most 400 words. Cover what changed, which screenshots you inspected, and what remains (with the owner
  who should fix it).
