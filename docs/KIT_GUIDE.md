# Champion Kit Authoring Guide

This project is a Godot 4.7 (GDScript) recreation of League of Legends' ARAM: Mayhem. Champion kits live in
`src/champions/kits/<alias_lowercase>.gd` and are loaded by path (no `class_name`). **Reference kits:
`src/champions/kits/ahri.gd` (ranged mage, skillshots, recasts) and `src/champions/kits/garen.gd` (melee,
empowered attack, spin channel, execute).** Read both fully before writing a kit.

## Ground rules
- Only create/modify your own kit files (`src/champions/kits/<alias>.gd`, optionally `<alias>_*.gd` helpers in
  the same folder). Do **not** edit core files (`src/core`, `src/match`, `src/ai`, `src/ui`, `kit_util.gd`, other
  kits). If you truly need a core change, implement a local workaround and describe the desired core change in
  your final report.
- Use authentic numbers from `data/champions/<alias>_game.json` (extracted from the real game files):
  `stats`, `spell_slots` (Q/W/E/R -> spell script names), `spells[script]` with `data_values`, `calcs` (readable
  formulas like `"BaseDamage + 0.5*AP"`), `cooldownTime`, `mana`, `castRange`, `castRangeDisplayOverride`,
  `castRadius`, `missileSpeed`, `mLineWidth`, `mCastTime`, `tooltip`. Sub-spells (missiles, buffs) are listed too.
  `data/champions/<alias>_client.json` has names/descriptions. Behaviour should match live League as closely as
  practical (use your League knowledge for mechanics the data doesn't spell out).
- Units: gameplay numbers are in **League units** (1 unit = 0.01 m). World positions are Godot meters.
  Convert with `G.U` (e.g. `range_units * G.U`). Ability fields `cast_range`, `ind_width`, `ind_radius`,
  `ind_length` are League units. `K.*` helpers take League units unless the name ends with `_m`.

## Structure of a kit
```gdscript
extends ChampionKit
func build_kit() -> void:
    c.attack_missile_speed = 1750.0   # 0 = melee (instant hit)
    c.attack_color = Color(...)       # basic attack missile color
    c.role = "mage"                   # mage, marksman, tank, fighter, support, assassin
    c.level_order = "QEWQQRQEQEREEWWRWW"   # bot skill order
    c.passive = MyPassive.new(); c.add_effect(c.passive)
    c.abilities[0] = init_ability(MyQ.new(), "Q")   # init_ability fills data/cooldowns/costs/range from json
    ...
func ai_tuning() -> Dictionary: return {"aggression": 0.6}   # optional
func anim_overrides() -> Dictionary: return {"run": ["run_haste"]}   # optional
```
`init_ability(ability, "Q", "OptionalScriptName")` loads json data for that slot. Afterwards you may override any
field in the ability's `_init()` (which runs first) or after the call.

### Ability (src/core/ability.gd)
Fields: `target_type` (Target.NONE/UNIT/POINT/DIRECTION), `target_side` (Side.ENEMY/ALLY/ANY/ALLY_OR_SELF),
`target_champions_only`, `indicator` (Ind.NONE/LINE/CIRCLE/CONE/RANGE), `ind_width`, `ind_radius`, `ind_angle`,
`ind_length`, `cast_range`, `cast_time` (windup; champion stands still unless `can_move_while_casting`),
`anim` (logical "spell1".."spell4" or a raw clip name from `assets/champions/<alias>/<alias>.anims.json`),
`anim_lock`, `resets_attack`, `uninterruptible`, `can_move_while_channeling`, `max_charges`/`charge_cd`.
- `dv("Name")` = data value at the current rank. `rv(array)` = per-rank array value. `ap()`, `ad()`, `bonus_ad()`.
- `execute(t)` runs after the windup. `t` = `{pos: Vector3, dir: Vector3, unit: Unit|null}`. **Always call
  `notify_cast(t)`** at the end (augments/items hook into it).
- Recasts: set `recast_window = seconds` inside execute; while > 0 the ability is castable again for free.
  Override `on_recast_expired()` (default starts the cooldown). `auto_cooldown() -> false` to control cooldown
  manually with `start_cooldown()`. `reduce_cooldown(s)`.
- Channels: `start_channel(duration, extra_dict)`, override `channel_tick(dt, ch)` and `channel_end(ch, interrupted)`.
- Toggles: set `toggled` (HUD shows it).
- `hit(target, amount, G.DmgType.MAGIC/PHYSICAL/TRUE, opts)` deals ability damage (opts: is_aoe, is_dot, tag...).
- `make_target(world_pos, hovered)` is how the controller builds targets; override for self-centred spells.
- `ai_consider(ctx) -> Dictionary`: return a target dict to make a bot cast, `{}` to skip. `ctx` is the
  BotBrain (`src/ai/bot_brain.gd`): `ctx.enemies`, `ctx.allies`, `ctx.enemy_minions`, `ctx.mode`
  ("lane"/"fight"/"retreat"), `ctx.focus`, `ctx.best_enemy_in_range(meters)`, `ctx.lowest_ally(meters, below)`,
  `ctx.predict(unit, seconds)`, `ctx.aim_at(pos, ability)`, `ctx.count_enemies_near(pos, meters, champs_only)`,
  `ctx.best_cluster_point(range_m, radius_m, min_count)`, `ctx.in_danger()`. Write a good `ai_consider` for
  every ability: bots must use the kit intelligently in teamfights (engage, peel, finish kills, escape).

### Effects & passives (src/core/effect.gd)
Passives/hooks extend `Effect` and override hooks: `on_tick(u, dt)`, `on_pre_damage_dealt(info)` (modify
`info.amount`/`info.mult`/`info.flat_bonus`), `on_pre_damage_taken`, `on_damage_dealt`, `on_damage_taken`,
`on_attack_launch(target)`, `on_attack_hit(target, info)` (on-hit), `on_ability_cast(ab, t)`, `on_kill`,
`on_takedown`, `on_death`, `on_respawn`, `on_level_up`, `get_stat_mods()` (return stat dict, see `Stats`),
`prevent_death(info)`. Show a counter on the passive icon by adding `func hud_counter() -> String`.
Stat keys (src/core/stats.gd): hp, hp%, hp_regen, mana, ad, ad%, bonus_ad%, ap, ap%, armor, armor%, mr, mr%,
as (bonus attack speed fraction), crit, crit_dmg, ms, ms%, range, ah, ult_ah, basic_ah, lifesteal, omnivamp,
armor_pen%, lethality, magic_pen, magic_pen%, tenacity, slow_resist, heal_power, size, dmg_amp, dmg_reduction.
Call `refresh_stats()` after changing dynamic stats. Permanent stacking passives must multiply gains by
`owner.permanent_stack_mult()` (an augment doubles them).

### Helpers: `K` (src/champions/kit_util.gd)
`K.line_missile(ab, from, dir, speed_units, range_units, {width, pierce, max_hits, minions, champions,
stop_on_champion, color, size, light, visual, on_hit(m,u), on_end(m,pos), on_move(m,dt), accel, max_speed})`,
`K.homing_missile(ab, from, unit, speed, on_hit, {color,size,visual})`, `K.arc_missile(ab, from, to, time,
on_land(m,pos), {...})`, `K.cast_pos(unit, height)`, `K.enemies_circle/line/cone(...)`,
`K.damage_circle(ab, center, radius_units, amount, type, {each, minion_mult, champs_only})`,
`K.delayed_circle(ab, pos, radius_units, delay, color, on_trigger(units, pos))`, CC: `K.stun`, `K.root`,
`K.silence`, `K.disarm`, `K.ground`, `K.charm(t, dur, src, slow)`, `K.fear`, `K.taunt`, `K.suppress`,
`K.sleep`, `K.knockup(t, dur, src)`, `K.slow(t, amount, dur, src, decays)`, `K.buff(t, id, dur, stats, src,
{name, icon, debuff, max_stacks, stack_mode, per_stack, hidden, cc})`, `K.haste(t, amount, dur, src, decays)`,
`K.shield(src, t, amount, dur, color)`, `K.grievous`, `K.dot(ab, t, total, dur, type, id, interval)`.
Unit displacement: `u.knockback(from_pos, dist_m, dur, src)`, `u.pull_to(pos, dur, src)`,
`owner.start_dash(dest, {speed (m/s) | duration, height, on_arrive(u), on_tick(u, k), anim})`,
`owner.teleport(pos)`. Untargetable: `owner.untargetable_count += 1` (and `-= 1` later).
Unstoppable (CC immune): buff with `cc = Buff.CC.UNSTOPPABLE`. Airborne check: `(u.cc & Buff.CC.AIRBORNE) != 0`.
Match services (`owner.match_ref`): `time`, `after(sec, fn)`, `add_ticker(duration, fn(dt) -> bool)` for zones,
`add_blocker(team, a, b, dur)` (projectile wall), `enemies_in_radius(team, center_m, r_m, champs_only)`,
`allies_in_radius`, `units_in_line`, `units_in_cone`, `add_unit(unit, pos)`, `add_fx(node, pos)`,
`camera_rig.shake(amount)`. Summons: `Summon.new()` + `setup(owner, name, {hp, ad, armor, mr, as, range, ms,
radius, height, model: "AnnieTibbers", lifetime, scale})` then `m.add_unit(s, pos)` (Tibbers is exported at
`assets/units/annietibbers`).

### Visuals: `Vfx` (src/vfx/vfx.gd)
`Vfx.orb(color, size, light, trail)`, `Vfx.sprite(color, size, energy, tex)`, `Vfx.emitter(color, amount,
lifetime, size, opts)`, `Vfx.burst(m, pos, color, radius, {sparks, ring, light})`, `Vfx.ring(m, pos, color,
radius_m, duration, thickness, fill)`, `Vfx.ground_circle(m, pos, radius_m, color, lifetime, fill)`,
`Vfx.beam(m, from, to, color, width_m, duration)`, `Vfx.hit_spark(m, pos, color, size)`,
`Vfx.aura(unit, color, radius_m, duration)`, `Vfx.rising(unit, color, duration, amount, radius)`,
`Vfx.stun_stars`, `Vfx.shield_bubble`, `Vfx.light(color, energy, range)`. Build richer effects by composing
these and plain MeshInstance3D/GPUParticles3D under a `VfxNode` (auto-frees after `lifetime`). Every ability
needs readable, satisfying visuals in the champion's colors (projectiles with trails, impact bursts, telegraphs
for delayed effects, a big moment for the ultimate). Keep effects bright (additive) but not screen-filling.

### League VFX (preferred): `LolVfx` (src/vfx/lol_vfx.gd)
Every champion's original League particle systems are imported to `data/vfx/<alias>.json` (+ textures/meshes in
`assets/vfx/`) by `tools/lol/extract_vfx.py`; shared systems (click marker, summoners, turrets, minions, relic,
structures) are in `data/vfx/shared.json`. Use these instead of procedural visuals:
- `LolVfx.spawn(m, name, pos, {"dir", "scale", "loop", "center", "length"})` world-space effect;
  `LolVfx.attach(unit, name, opts)` follows (and faces with) a unit; `LolVfx.make(name, opts)` for missile visuals.
  `center` raises the non-ground emitters (effects are anchored at the unit's feet); `length` sizes beams.
  Looping effects: keep the node and call `stop()` when the buff/zone ends (or assign it to `buff.vfx`).
- Automatic hooks (by League naming `<Alias>_Base_<key>`): `BA_mis`/`BA_crit_mis`, `BA_tar`/`BA_crit_tar`,
  `<K>_cas` (on cast), `<K>_mis` (K helper missiles), `<K>_tar` (spell damage). Override/disable per kit with
  `func vfx_map() -> Dictionary` (`""` disables a key); force one missile's visual with K helper opts `{"lol": name}`.
- Preview without disturbing the desktop: `tools/preview.sh 150 -- --champ=<Alias> --vfxtest=<Name1>,<Name2>
  --vfxdir=<dir>` (serialized, off-screen; screenshots in `%APPDATA%/Godot/app_userdata/ARAM- Mayhem/<dir>/`).

### Audio: `GameAudio` (src/audio/game_audio.gd)
League's SFX/VO/announcer are extracted to `data/audio/*.json` (+ `assets/audio/game/`, regenerate with
`python tools/lol/extract_game_audio.py --extras`). Attacks, casts, spell hits, deaths, kills, announcer lines and
structure sounds are hooked automatically; play anything else with `m.audio.play("<Wwise event name>", pos)`.

## GDScript gotchas (these cause compile errors)
- `var x := owner.something` fails: `owner` (and anything from untyped arrays/dicts) is untyped. Use
  `var x: float = ...` / `var u: Unit = ...` or plain `var x = ...`.
- Lambdas capture locals by value; use a Dictionary/Array for shared mutable state, and `var self_ref := self`
  to call ability methods inside lambdas. Multi-line lambdas inside dict arguments work (see ahri.gd).
- Inner classes (`class Foo extends Ability:`) are the pattern for abilities/effects.

## Testing (required)
- Headless simulation (imports, prints script errors, kills, champion states):
  `tools/sim.sh 180 --every=60 --champ=<Alias>` (the player slot is bot-controlled; your champion is the
  player). Fix every SCRIPT ERROR. Add temporary `print()`s to confirm each ability actually executes in bot
  hands, then remove them.
- Visual check: `"/d/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --path .
  --fixed-fps 60 -- --sim --time=75 --every=100 --shots=62,66,70 --champ=<Alias> --shotdir=<alias>` writes
  screenshots to `C:/Users/ancie/AppData/Roaming/Godot/app_userdata/ARAM- Mayhem/<alias>/` (open them with the
  Read tool). Always use your own --shotdir (other agents run in parallel).
  The first teamfight usually happens around 60-70s.
- When done, commit in your worktree branch: `git add -A && git commit -m "Kit: <Alias>"`.
