# QA findings: ARAM Mayhem vs live League ARAM (Howling Abyss)

Reviewer: [qa]. Read-only review, no game code changed. Every capture is at 2560x1440 via `tools/preview.sh`.

**Screenshot roots** (`%APPDATA%/Godot/app_userdata/ARAM- Mayhem/` = `C:/Users/ancie/AppData/Roaming/Godot/app_userdata/ARAM- Mayhem/`):
- `uitest/`: menu, champ select, loading, shop, scoreboard, pause and end flow (`--uitest`).
- `qa_sim1/`: 7-minute bot match, Jinx, seed 7, with the perf probe.
- `qa_kit_<Champ>/`: per-champion casts at max zoom (`src/debug/qa_fight.gd --qamode=kit`).
- `qa_fight/`, `qa_move/`, `qa_death/`: forced teamfight, movement/turning and death flow (same harness).

**Priorities**
- **P0**: breaks the experience.
- **P1**: clearly not League.
- **P2**: polish.

The status line under each entry is the evidence. Owner tags follow docs/FIDELITY_GAPS.md.

---

## P0: breaks the experience

### P0-1 Frame rate collapses in every teamfight (RTX 4080 SUPER, 1440p) [perf]
- **Seen:** PERF lines in `qa_sim1` (perf probe):
  - t=60: `fps=31 worst=148ms slow%=98`.
  - t=65: `fps=57 worst=139ms`.
  - t=75: `fps=59 worst=136ms`.
- **Seen:** the HUD FPS counter reads `FPS: 22` at 01:01 in `qa_sim1/shot_0062.png` and `FPS: 30` at 01:49 in `shot_0110.png`.
- **Seen:** during the same fights the GPU time is only 1.5-2.1 ms. The cost is on the CPU and script side:
  - `tick.champ` up to 17 ms
  - `u.think` up to 15 ms
  - `timers` up to 472 ms
  - `missiles` 13.9 ms
  - `vfx.spawn` 9.5 ms
- **League:** holds a locked 144+ fps on this hardware in a 10-player ARAM fight.
- **Area:** src/match/match.gd `_run_timers`, src/core/champion.gd tick, src/ai/bot_brain.gd think, src/vfx/lol_vfx.gd spawn. See P0-2 for the single worst spike.
- **Note:** other agents may have been running headless sims at the same time, so the absolute numbers may be inflated. The `timers` spikes below are real single-call costs either way.

### P0-2 Lux W shield expiry causes 165 ms and 472 ms hitches [perf][kits]
- **Seen:** `SLOW timer 165.0ms ... lux.gd:263,lux.gd:273,missile.gd:223` and `SLOW timer 472.0ms ... lux.gd:263,lux.gd:304,missile.gd:223` (qa_sim1 log). This is the `m.after(dur + 0.05, fx.stop())` lambda in `_shield()`.
- **Impact:** half-second freezes in fights whenever Lux is in the game.
- **Area:** src/champions/kits/lux.gd:250-265 (ticker plus timer per shielded unit, `LolVfx.stop`). Check what `stop()` does on `Lux_Base_W_tar_shield`.

### P0-3 Freed-lambda errors spam every fight [kits]
- **Seen:** `ERROR: Lambda capture at index 0 was freed. Passed "null" instead.` from `match.gd:193 _run_timers` dozens of times per match (qa_sim1 log). The first one follows a Veigar W (`kit_util.gd:128` delayed_circle, `veigar.gd:326`). Masteryi.gd:223 timers fire in the same window.
- **Area:**
  - `K.delayed_circle` captures `ab`/`on_trigger` objects that can be freed.
  - Timers should hold a WeakRef or check `is_instance_valid` before calling.
- **Effect:** at best wasted work, at worst damage or VFX silently dropped.

---

## P1: clearly not League

### P1-1 Dead champions (and dying minions) turn bleached white or grey
- **Seen:** `qa_sim1/shot_0062.png` and `shot_0070.png` (crop of 70: the bodies right of centre).
  - The corpses of Yasuo, Ahri and Master Yi are an almost untextured pale grey-white.
  - Dying caster minions look the same.
  - Live units being hit flash toward white. For example, the enemy outer turret in `shot_0175.png` reads cream-white.
- **League:**
  - A dead champion lies in its final death pose with its normal colours for the whole respawn timer.
  - Units have no white hit-flash. Hit feedback is the hit VFX and sound only.
- **Likely cause:** `Unit._update_visual` adds `flash` (white emission, champion.gdshader line ~53). If the unit dies while `hit_flash > 0`, nothing decays it any more (dead units probably stop calling `_update_visual`), so the body stays lit white.
- **Recommendation:** zero `flash` on death and greatly reduce or remove the flash on champions.
- **Area:** src/core/unit.gd:1730-1737, src/vfx/shaders/champion.gdshader.

### P1-2 Health relic area heal is a giant opaque green disc plus a procedural beam
- **Seen:** `qa_sim1/shot_0110.png`. A lime-green filled circle covers about 60% of the screen and hides every unit and health bar inside it. A flat white "beam" comes down from the top.
- **League:** a beam of light strikes the 850-unit area. The ground marker is a thin, mostly transparent ring.
- **Gameplay mismatches with League** (wiki: https://wiki.leagueoflegends.com/en-us/Health_relic):
  - The heal is 16% of missing HP and mana. The code uses 22% (`Rules.RELIC_BEAM_HEAL`).
  - The heal hits **all** champions in the area, including enemies. The code heals only the picker's team (relic.gd:81).
- **Area:**
  - src/match/relic.gd:75-78: replace `Vfx.ground_circle` (alpha 0.8) and `Vfx.beam` with League's ARAMHealthPickup beam / impact systems from the shared set.
  - src/match/rules.gd.

### P1-3 Kill announcements: text is tiny, overlaps the portraits and has no banner art
- **Seen:**
  - `qa_sim1/shot_0062.png`: "FIRST BLOOD!".
  - `qa_sim1/shot_0070.png`: "DOUBLE KILL!" with two stray red bracket glyphs above the portraits.
  - `qa_sim1/shot_0130.png` and `qa_sim1/shot_0200.png`: "AN ALLY HAS BEEN SLAIN". The killer and victim portraits sit directly on the text and the text runs over the portrait rims. In shot 200 the banner also overlaps the enemy turret's health bar.
- **League:**
  - The announcement is a large banner at about 20% of screen height.
  - The killer portrait is on the left and the victim on the right, inside an ornate team-coloured (blue/red) frame.
  - The text sits in its own row below the portraits, in large gold Beaufort.
  - Multikills get the red/gold multikill banner.
- **Area:** src/ui/hud.gd `_draw_announcement` (~1131-1180). The background frame textures are probably not resolved (the stray red glyphs are a mis-sliced texture).

### P1-4 Kill feed overlaps the ally portrait column
- **Seen:** `qa_sim1/shot_0200.png`. With 5 kill-feed rows, the rows run to the right screen edge and sit on top of the teammate portraits and respawn timers (x 1930-2000 at display scale).
- **League:** the kill feed is right-aligned *left of* the ally frames. It never covers them and holds at most about 5 entries, which fade after a few seconds.
- **Area:** src/ui/hud.gd kill feed (hud.Feed) layout and its right anchor.

### P1-5 Malphite: black jagged quads around him (VFX blend error)
- **Seen:** `qa_sim1/shot_0062.png` (crop62). Solid black shard silhouettes, about 300x250 px, are drawn around Malphite during his Q/E.
- **League:** these Malphite effects are additive (the brown/amber rock shards glow, there is no black matte).
- **Area:** src/vfx/lol_vfx.gd blend mode for the particular Malphite emitter. Check `qa_kit_Malphite/` frames to identify it.
- **Update 2 evidence:** `qa_kit_Malphite/kit_Q_08..kit_Q_12`: the thrown Q boulder is a solid black ellipse (no rock texture, no glow). `kit_E_06`: the E slam bursts a cloud of red thorn/leaf-shaped particles (League: tan dust ring and ground shockwave). `kit_R_00` and `kit_R_02`: R landing marker is a flat opaque orange ellipse (see P1-6); `kit_R_08`: red spike burst on impact.

### P1-6 Procedural (non-League) telegraphs and decals mixed with League VFX
- **Sources:** grep of `Vfx.ground_circle` / `Vfx.ring` / `Vfx.sprite` / `Vfx.beam` in kits and match code:
  - veigar.gd:326 W uses `K.delayed_circle`, which draws a violet filled circle at alpha 0.7 *on top of* League's `Veigar_Base_W_cas` telegraph.
  - malphite.gd:571 draws an opaque orange R landing circle (alpha 0.8). Enemies do not see a ground circle for Malphite R in League.
  - annie.gd:779/786 rings. A big orange dashed ring under Tibbers is visible in `qa_sim1/shot_0175.png`.
  - veigar.gd:95/156, malphite.gd:212, jinx.gd:628 sprites.
  - structure.gd:120 ring on structure death.
  - summoners.gd:389.
  - item_fx.gd (several).
- **League:** every one of these effects is a textured particle system. There are no flat-coloured discs.
- **Area:** the listed lines. Replace them with the League system names, or delete them where League already shows the effect.

### P1-7 Loading screen: does not follow League's layout or timing
- **Seen:** `uitest/05_loading.png`.
  - Ten cards are shown in two rows.
  - Only the player's card has summoner spell icons; bots show none.
  - There is no skin name, no summoner name, no rank border and no champion-mastery banner.
  - Each card shows 100% almost immediately. The screen is held for a fixed 1.6 s, then freezes for about 3-4 s during the blocking match build (`LolVfx ... prebuilt` lines add up to ~3.3 s). During that freeze the percentages stop animating.
  - The enemy cards slide in staggered, and in the shot the last cards (Ezreal) are still invisible. An empty Ezreal card is visible at 1.9 s.
- **League:**
  - Each card shows the splash loading art, summoner spells, the summoner name with the skin name above it, and the mastery / rank border.
  - The per-player % climbs smoothly to 100.
  - The screen holds until every player is loaded and only then cuts to the game, with no frozen frame.
- **Area:** src/ui/menu/loading_screen.gd. Move the VFX prebuild into the threaded load so the progress bars reflect it. Give bot cards their summoners.

### P1-8 Victory/Defeat screen is a placeholder circle, not League's crest
- **Seen:** `uitest/08_victory.png`. A flat orange disc with a few ray lines and the word VICTORY.
- **League:** the camera pans to the exploding enemy Nexus. After it explodes, the large animated VICTORY/DEFEAT crest appears (gold winged emblem for Victory, red broken emblem for Defeat), followed by the "Continue" button.
- **Area:** src/ui/menu/end_screen.gd. The real flow is checked separately in the endgame section.

---

## P2: polish

### P2-1 Scoreboard keystone rune slot is an empty black circle
- **Seen:** `uitest/06c_scoreboard.png`. Every champion has a black circle at the lower-left of the portrait.
- **League:** the keystone rune icon sits there.
- **Area:** src/ui/hud/hud_scoreboard.gd. Either show a keystone or remove the circle.

### P2-2 End-of-game stats: MVP badge given to a 0/0/0 player
- **Seen:** `uitest/09_stats.png`. "MVP" sits on Darius with 0/0/0, 0 damage and an empty inventory.
- **League:** has no MVP tag in the post-game screen. If it is kept, compute it from a score, not from the player slot.
- **Area:** src/ui/menu/end_screen.gd.

### P2-3 Champ select role tags not from Riot data
- **Seen:** `uitest/03_champ_select.png`. Miss Fortune is tagged MARKSMAN + MAGE.
- **League:** Riot data tags Miss Fortune as Marksman only. Check every champion against data dragon `tags`.
- **Area:** src/ui/menu/champ_select.gd and data/champions/*_client.json.

### P2-4 Champ select has no countdown timer
- **Seen:** `uitest/03_champ_select.png`.
- **League:** ARAM champ select shows a large countdown (about 0:50 down to 0) at the top centre, followed by the "Final Moments" phase.
- **Area:** src/ui/menu/champ_select.gd.

### P2-5 Audio: missing or unmatched sound events (logic check against data/audio/*.json)
Events that are never found:
- `Play_sfx_SummonerDot_OnCast`: Ignite has no sound.
- `Play_sfx_HA_ChaosMinionSiegeBasicAttack_OnCast`: red siege minion attacks are silent.
- `Play_sfx_<Champ>_Death3D_cast` is missing for Annie, Malphite, MissFortune, Sona and Veigar. The death sounds of those champions exist under other names; grep `data/audio/<champ>.json`.

Gaps from the matching logic in `GameAudio._index_champion`:
- Master Yi Q has **no cast sound**. The event is named `AlphaStrike_missilecast`, which does not end in `_cast`.
- No hit sounds for:
  - Lux Q: `LuxLightBindingMis_OnBuffActivate`
  - Lux W
  - Lux R: `LuxRBeam_beammiddle` / `beamend` are never played.
  - Garen Q/W, Jinx E, MF W/E/R, Veigar E, Yi W/E/R.
- Loop events such as `Veigar_EventHorizon_loop` and `MasterYi_Highlander_trail` are never started.

- **Area:** src/audio/game_audio.gd:211-244 (suffix rules). Add `missilecast`, `OnBuffActivate` (for the "Mis" buff) and `beam*` rules.
- **Note:** `_play()` returns silently on unknown events. A one-time `push_warning` would make these visible in logs.

---

# Update 2 (continuation by second [qa] agent)

New harness: `src/debug/qa_flow.gd` (modes end / relic / gates / lane / brush / zoom / walk). Kit captures now exist for more champions in `qa_kit_<Champ>/`.
Numbering continues; the earlier P0-1..P2-5 stay valid unless marked below.

## New P0

### P0-4 Hexgates (frost-gates) are inert props [env][match]
- **Seen:** `src/match/match.gd:893` `_update_hexgates()` is `pass`; nothing else in src/ references hexgates. `build_props` only places the model and plays idle. There is no channel, no dash, no cooldown, no change of gate position after the outer turret falls.
- **League:** (wiki Howling Abyss) after the base gate drops a frost-gate behind the Nexus carries the team toward mid (channel, then untargetable dash); when the Outer turret falls the gate moves in front of the inhibitor turret. It is the core "get back to lane" mechanic of the map.
- **Area:** src/match/match.gd `_build_props` / `_update_hexgates`, src/player/player_controller.gd (right-click on gate), bot_brain (bots never use it).


### P0-5 Nexus does not explode: the end sequence shows only procedural gold rings around an intact nexus [env][ui]
- **Seen:** `qa_end/end_00..end_29` (harness kills the enemy Nexus at 2560x1440). The crystal stays standing, undamaged, for the whole 8 s. The only feedback is two expanding flat orange rings (`structure.gd:120` ring) with a few sparkles, then the VICTORY crest fades in over the intact nexus (`end_18..end_after_banner`). The turrets' red range rings are still drawn on the ground during the end sequence.
- **League:** the Nexus detonates (white flash, shock-ring, crystal shards and debris), turrets and minions in its base blow up, the camera holds on the rubble, then the VICTORY/DEFEAT crest. The HUD fades out, the world does not show gameplay overlays (range rings).
- **Area:** src/core/structure.gd death handling for G.Kind.NEXUS (play the death anim / swap to the destroyed model / use the League `*_nexus_death` VFX), src/match/match.gd `end_game` (hide world overlay incl. range rings; start end screen after the explosion).
- **Also:** `end_screen.gd` triggers the crest at a fixed 2.4 s of real time regardless of whether the explosion has finished (it fades in as early as end_16 while the rings are still expanding).

### P0-6 A single Jinx E (Flame Chompers) kit run logs 152 freed-lambda errors, one per frame [kits]
- **Seen:** `scratchpad/kit_Jinx.log`: `ERROR: Lambda capture at index 5 was freed. Passed "null" instead.` at `match.gd:132` (the ticker loop) every frame while chompers are out. A ticker whose captured unit is freed is still `is_valid()`, so it is called until it expires. This is the per-frame variant of P0-3.
- **Area:** src/champions/kits/jinx.gd:657 `m.add_ticker(arm + dur, func(dt) ...)`; `match.gd` ticker loop should drop a ticker when the capture is freed (wrap in a weakref or have tickers return false when `not is_instance_valid(owner)`).
- Lux W/E in `qa_kit_Lux` logs the P0-3 error twice per cast (match.gd:193).


## New P1

### P1-9 Lux: staff detaches from her hand during R (and drifts during Q)
- **Seen:** `qa_kit_Lux/kit_R_02..kit_R_14` (crop box 700,300,1900,950): the brown staff lies/hovers on the ground a body-length away from Lux for the whole R cast and recovery. In `kit_Q_05` it also points sideways away from the hand.
- **League:** the weapon stays in her hand through every cast and recovery.
- **Area:** src/champions/kits/lux.gd (socket/weapon bone handling during spell anims) / src/core/anim_graph.gd.

### P1-10 Lux Q and R read weakly (washed-out)
- **Seen:** `qa_kit_Lux/kit_Q_07..kit_Q_12`: Light Binding is a faint rainbow smear, nearly invisible on the pale floor; the real effect is a dense bright orb with a long rainbow tail and a clear bind ring on hit. `kit_R_04..kit_R_08`: the laser is a translucent diagonal wash, not a thick white beam, and a thin blue circle (telegraph) stays up for the whole cast. In `kit_R_*` the beam does not run through the target (Ezreal at the left dummy) but passes above and to the right of it.
- **League:** Final Spark is an opaque white-gold beam about 200 units wide that visibly clips everything in its line.
- **Area:** src/vfx/lol_vfx.gd blend / brightness for Lux_Base_Q_mis, Lux_Base_R_*; lux.gd aim direction for R.

### P1-11 Jinx R launch effect is an oversized pink-orange blob
- **Seen:** `qa_kit_Jinx/kit_R_13` and `kit_R_14`: a ~250 px smoke-and-glow cloud sits on top of Jinx and the missile; the rocket itself is not readable.
- **League:** a clearly shaped rocket with a tight exhaust trail; the large effect only appears at the impact.
- **Area:** src/champions/kits/jinx.gd R, LolVfx `Jinx_Base_R_*` scale.

### P1-12 Persistent blue spiral ring under a standing Yasuo
- **Seen:** `qa_kit_Lux/kit_Q_00..15` (the right dummy is Yasuo): a large animated cyan vortex disc is drawn at his feet for the entire capture while he is idle and uncast.
- **League:** Yasuo has no ground vortex when idle; only the passive shield flash and Q3 whirlwind exist.
- **Area:** src/champions/kits/yasuo.gd (a passive/Q3 loop left attached).

### P1-13 (verify) Idle champions hold one frozen wide-legged pose
- **Seen:** `qa_kit_Lux/kit_idle.png` to `kit_Q_15.png`: Ezreal and Yasuo stand in a mid-stride pose with white speed streaks for 16+ frames (about 1.5 s) without moving. `qa_kit_Jinx`: Ezreal keeps his crouch pose.
- **Note:** Jinx in `qa_death/respawn_00..05` also holds one pose for 1.2 s, so it may simply be a very slow idle clip. Compare to League where idle visibly loops (breathing, weapon sway) within 1 s.
- **Cause (to confirm):** harness calls `teleport()` then `issue_move(own position)`. If the move target is within the arrival radius the unit may stay in the "moving" state and the run clip never returns to idle.
- **League:** a unit that reaches its destination returns to idle within 1-2 frames.
- **Area:** src/core/unit.gd issue_move / stop_moving / anim state in anim_graph.gd.

### P1-14 Spurious blood and slash VFX on Ezreal during his own R
- **Seen:** `qa_kit_Ezreal/kit_R_06..kit_R_12`: red blood splatter on the floor under Ezreal plus white crescent slash arcs and "13" damage ticks, while no one is attacking him. The R beam toward the dummies is not visible in these frames (a bright burst appears at his feet instead).
- **Area:** src/champions/kits/ezreal.gd R. Check whether Darius or Garen dummy hit VFX are being spawned on the wrong unit, and the R beam direction.

### P1-16 Brush: was fully opaque pure white (hid the champion); now translucent but still too bright and unshaded [env]
- **Seen:** `qa_move/move_zoomin*.png` (earlier build, 05:20): Jinx completely covered by opaque, flat white stalks, only her health bar visible. `qa_brush/brush_in_00..brush_out_05` (build at 05:30, after another agent's change): brush is now semi-transparent and Jinx is visible through it, with a ghosted lower body. In every wide shot the brush is still the brightest, flattest object on the map.
- **League:** soft pale-blue frost grass from translucent cards with shading; allied units in brush are drawn at reduced alpha with an outline, no hard white.
- **Area:** map_builder brush material (albedo/emission), MapAmbient. Please re-check the champion-in-brush alpha and the enemy-in-brush hiding (not exercised here).

### P1-17 Teamfight readability: blown-out white starbursts and opaque orange spheres
- **Seen:** `qa_fight/fight_20`: a ~300 px opaque orange sphere (Annie/Malphite-like) covers three units. `fight_25..fight_35`: a ~300 px pure-white starburst (no colour, no shape) hides Garen and Darius for 1.5 s. `fight_05..fight_15`: pink glowing orbs with orange crescent arcs everywhere.
- **League:** AoE effects are bright but keep their silhouette and colour; they never fully obscure units. Allied vs enemy effect colours are readable.
- **Area:** additive stacking in lol_vfx.gd (no per-effect intensity cap; look at which system is the white one by stepping `fight_24..27`), Malphite R / Annie R / Garen R.

### P1-18 Silent systems: relic pickup / beam strike, shop open/close, poro bounce, hexgate, footsteps, minion and structure feedback
- **Seen (code):** `data/audio/shared.json` / `map12.json` contain `Play_sfx_Env_Map12_Crepe_healthpickup_cast`, `Play_sfx_env_map12_ha_ap_viking_shop_open` / `_close` / `_aura`, `Play_sfx_env_map12_ha_ap_poro_base_jump` / `_explosion`, `Play_sfx_Env_Map12_SRX_Hextech_Hexgate_*`; none of them are referenced anywhere in `src/` (grep). relic.gd has no audio call at all.
- **Missing categories vs League:** footsteps (League has soft ground footsteps for champions and minions), minion death / spawn horn, gold-coin tick on last hit, item active sounds, turret target-lock warning, recall/teleport, low-health, level-up for allies.
- **Area:** src/audio/game_audio.gd (add handlers), relic.gd, shop_panel.gd (open/close), match.gd (props: poro, shopkeeper aura when near the shop).

### P1-19 Roster is only 14 champions, bench shows 9
- **Seen:** `uitest/03_champ_select.png`, `data/champions/` (14 *_game.json).
- **League:** 160+ champions, ARAM bench of 10 random champions, each with the player's reroll pool.
- **Area:** scope item for the lead (content), not a bug.

## New P2

### P2-6 Floating damage numbers stay glued to the health bar for over a second [world-ui]
- **Seen:** `qa_kit_Lux/kit_Q_*` (consecutive frames, 0.08 s apart): "48" stays on Ezreal's bar for 16 frames (~1.3 s) without rising; "81" stays on Lux's own bar.
- **League:** numbers spawn above the head, rise and fade in about 0.8 s.
- **Area:** src/ui/world_overlay.gd `damage_number`.

### P2-8 "TURRET DESTROYED" and the other non-kill announcements are small, lack the gold banner art, and overlap the health bar of whatever unit is below
- **Seen:** `qa_sim2/shot_0130.png`: "AN ALLY HAS BEEN SLAIN" is tiny, small portraits sit on the text.
- **League:** a broad gold banner at the top-centre, with the "+150 gold" popup.
- **Area:** src/ui/hud.gd `_draw_announcement` non-kill branch.

### P2-9 Minion first wave at 0:40 and passive gold rate differ from the wiki
- **Seen:** log `[00:40] Minions have spawned!`; `rules.gd` FIRST_WAVE_TIME=40, PASSIVE_GOLD_PER_SEC=8.5.
- **League (wiki ARAM):** first minion spawn 0:50, waves every 25 s early then shorter, passive gold 60 per 10 s from 1:00.
- **Area:** src/match/rules.gd (confirm intended "Mayhem" values with the lead).

### P2-10 Debug "FPS: N 0ms" readout is permanently drawn under the score at top right
- **Seen:** every `qa_sim1` and `uitest` HUD shot.
- **League:** off by default.
- **Area:** src/ui/hud.gd.

### P2-11 Respawn has no League respawn effect; a big orange bubble plays elsewhere
- **Seen:** `qa_death/respawn_00..05` (player respawn at the fountain): Jinx just appears, no light pillar / ring / sound cue. On the other hand `qa_kit_Jinx/kit_W_00`, `kit_E_00`, `kit_R_00` (dead dummy revived by the harness): a large opaque orange sphere plus red ring covers the revived champion for about half a second.
- **League:** a gold-white respawn light burst at the fountain plus the "Respawn" sting, nothing on units that are teleported.
- **Area:** src/core/champion.gd `respawn`, LolVfx effect used; check which system the orange bubble is (probably a spawn shield, Summoner Barrier, or Yasuo/Ahri passive VFX attached on revive).

---

# Update 3 (second [qa] agent)

Evidence note: other agents edit the code in parallel, so some runs log "Compilation failed" (`ItemText`, `ItemFxExtra`, `f_bold` errors). The in-match captures below still ran; `uitest` was intermittently unavailable.
Perf note: in `qa_sim2` (Garen, seed 11, 2560x1440, 4 min) the 130-145 ms "worst" frames on idle windows (t=45, 80, 105, 135, 165, 225, 240) all line up with the harness screenshot saves, not with game code. Ignore them. The real stalls are below.

## Additional P0

### P0-7 Fights still collapse the frame rate (re-measured with a different seed)
- **Seen:** `qa_sim2` PERF: t=60..80 fps 102-137 (fighting=4-10); t=110-115 fps 91-102; t=150 fps 114 with slow%=5; t=200 fps=37 slow%=88; t=205 fps=33 slow%=90, proc=76.7 ms.
- **Cost centres at t=205:** `tick.champ` avg 4.7 ms / worst 60.8 ms, `u.cast_atk` worst 59.1 ms, `cast.exec` worst 58.7 ms, `u.think` worst 20.6 ms, `tick.turret` worst 14.5 ms, `u.visual` worst 14.8 ms. GPU is only 1.4-16 ms. SLOW log lines: `death.on_died 47.0ms Outer Turret`, `missile 52.0ms Miss Fortune attack`, `missile 10.4ms Lux Light Binding`, and nine `death.on_unit_died` at 3-4 ms per kill.
- **League:** constant 144 fps in the same fight.
- **Area:** one cast executing for about 59 ms (first-use cost: material, shader or node instantiation inside `cast.exec`; see `LolVfx.spawn` and the `K.*` helpers), the turret death handler (`structure.gd` / `turret.gd` `on_died`, 47 ms), Miss Fortune auto-attack missile creation. The same log has 12 freed-lambda errors (P0-3).

## Additional P1

### P1-20 Living units flash pale-white when hit (confirms P1-1 on live units)
- **Seen:** `qa_kit_MissFortune/kit_E_15` and `kit_R_06..kit_R_15`: the Annie and Jinx dummies turn almost white while damage ticks continue (1-2 s). `qa_kit_Ezreal/kit_Q_10..14`, `qa_kit_Yasuo/kit_Q_06`: the dummy is bleached cream. `qa_sim2/shot_0075`: Leona and Garen are glowing white blobs.
- **League:** no whole-model flash.
- **Area:** src/vfx/shaders/champion.gdshader flash term, unit.gd hit flash. Cap it at about 10% for 0.05 s or remove it.

### P1-21 Miss Fortune W (Strut) draws a permanent pink starburst at her feet
- **Seen:** `qa_kit_MissFortune/kit_W_00..kit_W_15` and `kit_E_00..kit_E_12` (the buff persists): a pink radial starburst of about 150 px stays on her for more than 3 s.
- **League:** Strut has only a faint speed trail and a small buff glow.
- **Area:** missfortune.gd W buff VFX attach (a one-shot cast effect probably left looping).

### P1-22 Miss Fortune R (Bullet Time) reads as an orange scribble and a big pale ring
- **Seen:** `qa_kit_MissFortune/kit_R_03..kit_R_12`: the bullets are one orange scribble crossing the dummies, plus a faint cyan ring/cone outline for the whole duration. MF drops into a low crouch.
- **League:** a clear cone of many small bullets with impact sparks on each target and a golden cone marker.
- **Area:** missfortune.gd R, LolVfx `MissFortune_Base_R_*`.

### P1-23 Q missiles of Annie, Veigar and Ahri are barely readable
- **Seen:** `qa_kit_Annie/kit_Q_00..kit_Q_10`: Disintegrate is a small orange ring and comet with no fireball. `qa_kit_Veigar/kit_Q_05..kit_Q_10`: Baleful Strike is a thin purple dot, and "FLAP" in pink capital letters is drawn on top of his own health bar (`kit_Q_10`, `kit_Q_15`). `qa_kit_Ahri/kit_Q_05..kit_Q_10`: Orb of Deception is a tiny pale rainbow smear, no orb.
- **League:** Annie Q is a clear fireball, Veigar Q a purple orb with a trail, Ahri Q a glowing orb with a returning ring. None of them show floating text.
- **Area:** annie.gd, veigar.gd (`fx_text` "FLAP"), ahri.gd, LolVfx missile scale.

### P1-24 Destroyed turrets leave a cream-white heap of rubble that looks unfinished
- **Seen:** `qa_sim2/shot_0235.png`: after the outer turret fell, a long fallen heap of cream and blue ice-crystal pieces, some with flat cream faces, lies across the bridge, with black triangular shards in the air.
- **League:** dust cloud, then a low dark stone debris pile with no bright cream material.
- **Area:** src/core/turret.gd and structure.gd rubble state, rubble submesh materials (albedo too bright).

### P1-25 Minions: small, pale and hunched; health bar is a bare teal line
- **Seen:** `qa_sim2/shot_0075` and `shot_0130`: blue-team melee and caster minions are tiny (about 55 px tall at 1440p), mostly pale grey with a few blue patches, their run pose is bent forward, and the health bar is a 1-pixel teal line with no frame.
- **League:** clearly team-coloured (blue vs red) armoured minions, an upright run cycle, and a framed health bar.
- **Area:** minion.gd model scale and team tint, world health bars (minion variant), `Assets.unit_model`.

### P1-26 Relic area-heal ground disc stays up and fills the screen
- **Seen:** `qa_relic/relic_pickup_05..relic_beam_12`: the green disc appears at pickup and covers the whole view for about 6 s (2.5 s telegraph and 3 s after), hiding the health bars. Heal numbers "+41 +37" are tiny.
- **League:** a thin ring while the 2.5 s beam is on its way, then the beam strike.
- **Note:** the pickup icon (floating blue health pickup) is right (`relic_idle_00`). See P1-2 for the 22% vs 16% and the enemy-heal mismatches.

### P1-27 Kill feed shows two rows of six icons per kill and overlaps the ally portraits
- **Seen:** `qa_sim1/shot_0062`, `shot_0110`, `qa_sim2/shot_0130` (right edge, x 1740-2000 at 2000-wide display): each kill is two rows of 6 icons (assisters, killer, sword, victim) in a blue/red frame.
- **League:** one compact line per kill (killer, sword icon, victim); assists are not shown. At most 5 rows.
- **Area:** src/ui/hud.gd kill feed.

## Additional P2

### P2-13 Poro scale and placement is inconsistent
- **Seen:** `qa_sim1/shot_0062.png` (x 1540-1620, y 660-740): a poro stands on top of a base wall at about twice the size of the poros in the lane.
- **League:** poros are small, sit on specific props and bounce when approached (`Play_sfx_env_map12_ha_ap_poro_base_jump` exists in data, but is never played).
- **Area:** src/match/match.gd `_build_props`, map_props.gd.

### P2-14 Wind streaks are drawn as grey diagonal sheets
- **Seen:** `qa_lane/lane_b_06..lane_b_18` (top-right quarter): translucent grey diagonal bands cross the screen at a constant angle.
- **League:** subtle snow flurries only.
- **Area:** src/env/map_ambient.gd wind VFX scale and alpha.

### P2-15 Turret range rings stay on the ground through the end sequence
- **Seen:** `qa_end/end_before..end_29`: thin red rings around the enemy nexus turrets stay visible even under VICTORY.
- **League:** a ring appears only when a champion is near the turret, and it is hidden on the end screen.
- **Area:** world_overlay.gd / the 3D range decal; `match.gd end_game` hides `overlay` but not the decals.

### P2-16 Nexus shows an "Immune" label and a full health bar at the moment it is killed
- **Seen:** `qa_end/end_before.png` (nexus bar says "Immune" while the turrets guard it), then no health drain. League shows the shield/immune bar only while turrets stand, and drains the nexus bar before it explodes.
- **Area:** structure.gd, hud world bar (harness kills it directly, so check the real sequence in a normal match).

### P1-28 Weapons detach from the hand during casts on several champions (Lux, Sona, Darius), not just Lux
- **Seen:** `qa_kit_Sona/kit_R_08`, `kit_R_12`: the golden etwahl lies on the ground more than a body-length from Sona and stays there through recovery. `qa_kit_Darius/kit_Q_04`, `kit_Q_12`, `kit_E_04`: the axe floats above or beside him with no arm holding it (Q_12: axe 1.5 body-lengths away on the ground). Same behaviour as Lux's staff (P1-9).
- **League:** weapon stays in the hand (or follows the bone) in every clip.
- **Likely cause:** the weapon is a separate mesh parented to a bone whose animation in the cast clip is not the hand bone, or the model is hidden/shown as a prop. Check the shared weapon-socket code in unit.gd / anim_graph.gd, not each kit.

### P2-18 Spell-cast pose recoveries hold an extended pose for more than 1 s after the effect ends
- **Seen:** `qa_kit_Sona/kit_R_08..kit_R_15`, `qa_kit_MissFortune/kit_R_09..kit_R_15`, `qa_kit_Lux/kit_R_08..kit_R_14`: the champion stays in the last cast frame while the VFX is long gone.
- **League:** a cast animation ends at its recovery frame and returns to idle/run within ~0.3 s (can be cancelled by moving).
- **Area:** anim_graph.gd one-shot clip end / state return.

### P2-21 Shop was empty in a build captured during another agent's edit (now fixed; keep as a regression check)
- **Seen:** `uitest/06b_shop.png` at 05:34 (1080p): panel with no items. Re-captured at 05:44 (2560x1440): shop fully populated (Suggested items, Full build, Builds into, Purchase button). So it was a transient compile break (`ItemText` / `ItemFxExtra` / `ItemDB.bot_next_purchase`).
- **Minor remaining:** at 1440p the Stridebreaker icon is almost black, and the shop covers the centre of the screen (League's shop is a bottom-left/centre panel that leaves the minimap visible).
- **Area:** src/ui/shop_panel.gd; run `--uitest` after every item-system change.

### P2-19 Loading screen: overall progress bar overlaps the per-card percentages and the tip
- **Seen:** `uitest/05_loading.png` (05:34): a long gold bar at y ~1008 runs across the bottom row of "100%" labels (the labels are half covered), and the TIP line sits directly under it. Every card shows 100% from the first frame, so the bars carry no information. This build gives every bot its two summoner spells (improves P1-7); skin names, summoner names and mastery frames are still missing.
- **League:** each card has its own bar that rises independently, the percent sits inside the card, and the tip is separate.
- **Area:** src/ui/menu/loading_screen.gd.

### P2-20 Champ select: only 9 bench slots, no skin picker, no timer, bots labelled "Bot"
- **Seen:** `uitest/03_champ_select.png`: nine bench champions, "YOUR TEAM" shows "Bot" under each ally name, no enemy team list, no skin selection, no countdown, tags "TANK MAGE" under Malphite (League: Tank, Fighter), a "BOT DIFFICULTY" panel with "Insane" selected.
- **League:** ten-champion ARAM bench, skin/chroma carousel, summoner-name cards, 10-champion lobby, countdown.
- **Area:** src/ui/menu/champ_select.gd, data/champions/*_client.json (tags).
