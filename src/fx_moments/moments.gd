class_name Moments
extends Node
## [juice] Key-moment director: League-style death / respawn / kill / end-of-game feedback that no single unit
## or kit owns. Created by GameAudio.setup() (so the match needs no extra wiring) and driven by G signals.
##
##  - death screen: the player's grey world (tone + fade timing, see drive_gray / death_gray.gdshader)
##  - respawn: League's HA_Respawn light pillar at the fountain (Global.wad, data/vfx/moments.json)
##  - kills: coin burst (ChampBountyGet_T1 / _T2) over the champion that took the bounty
##  - end of game: the camera glides to the falling nexus and settles on the explosion
##
## Everything is event driven (no per-frame work except the gray fade while it is non-zero).

const SET := "moments"

# ---- death screen (League desaturates the world the moment you die and lifts it as soon as you respawn)
const GRAY_IN := 0.55          ## seconds to full desaturation
const GRAY_OUT := 0.3          ## seconds to colour once respawned
## [look2] DEATH_EFFECT_APPLY_FRACTION while dead: 0.8, measured on the live dead frame (docs/ENV_LOOK.md section 6:
## chroma kept 0.485 = 1 - 0.8 * F^2). Every map's DeathRecapGreyscaleConfig carries 0.2 (= 1 - F?) next to 3.0 / 1.5.
const GRAY_MAX := 0.8

var m = null
var gray := 0.0
var _gray_phase := 0.0         ## 0..1 linear progress, eased when applied
var _end_started := false


func setup(p_match) -> void:
	m = p_match
	LolVfx.load_set(SET)
	G.champion_killed.connect(_on_champion_killed)
	G.announcer_event.connect(_on_announcer)
	G.match_over.connect(_on_match_over)
	m.after(0.5, _spawn_in)


# ===================================================================== death screen
## Called every frame by Match._update_death_gray. Returns nothing; owns the ColorRect + shader params.
func drive_gray(delta: float, rect: ColorRect) -> void:
	if rect == null or G.player == null:
		return
	var want: bool = G.player.dead and not m.over
	var speed: float = (1.0 / GRAY_IN) if want else (-1.0 / GRAY_OUT)
	_gray_phase = clampf(_gray_phase + delta * speed, 0.0, 1.0)
	# ease: fast start, soft landing (death) / quick pop back to colour (respawn)
	var k := _gray_phase
	gray = (1.0 - pow(1.0 - k, 2.2)) if want else k * k
	gray *= GRAY_MAX
	rect.visible = gray > 0.002
	if rect.visible:
		var mat := rect.material as ShaderMaterial
		mat.set_shader_parameter("amount", gray)


# ===================================================================== kills
const BIG_KEYS := ["shutdown", "double_kill", "triple_kill", "quadra_kill", "penta_kill", "first_blood", "killing_spree",
		"rampage", "unstoppable", "dominating", "godlike", "legendary"]
var _pend_killer = null
var _pend_big := false


func _on_champion_killed(_victim, killer, _assisters) -> void:
	if m == null or killer == null or not is_instance_valid(killer) or killer.kind != G.Kind.CHAMPION:
		return
	_pend_killer = killer
	_pend_big = false
	_flush_kill.call_deferred()      # Match emits announcer_event right after champion_killed, same frame


func _on_announcer(key: String, _ally: bool) -> void:
	if key in BIG_KEYS:
		_pend_big = true


func _flush_kill() -> void:
	var killer = _pend_killer
	_pend_killer = null
	if killer == null or not is_instance_valid(killer) or not _seen(killer):
		return
	# League: the bounty bursts over the killer (a bigger burst for shutdowns / multikills / first blood)
	var nm := "ChampBountyGet_T2" if _pend_big else "ChampBountyGet_T1"
	if LolVfx.has(nm):
		# world-space (not attached) so nothing lingers on the unit once the burst is over
		LolVfx.spawn(m, nm, killer.global_position, {"max_life": 2.6})


func _seen(u) -> bool:
	if G.player == null:
		return true
	return u.team == G.player.team or u.visible_to[G.player.team]


# ===================================================================== respawn
## Game start: League's HA_Spawn light pillar on the platform for the champions in view (the enemy fountain is far away).
func _spawn_in() -> void:
	if m == null or not LolVfx.has("HA_Spawn"):
		return
	for c in m.champions:
		if G.player != null and c.team != G.player.team:
			continue
		var p: Vector3 = c.global_position
		LolVfx.spawn(m, "HA_Spawn", Vector3(p.x, m.nav.height_at(p) if m.nav != null else p.y, p.z), {"max_life": 6.4})
	if m.audio != null:
		m.audio.play("Play_sfx_Spawn_Base_buffactivate", G.player.global_position if G.player != null else null, -6.0, 0.0)


func on_respawn(c) -> void:
	if m == null or c == null or not is_instance_valid(c):
		return
	var nm := "HA_Respawn"
	if LolVfx.has(nm):
		var p: Vector3 = c.global_position
		LolVfx.spawn(m, nm, Vector3(p.x, m.nav.height_at(p) if m.nav != null else p.y, p.z), {"max_life": 6.4})


# ===================================================================== end of game
func _on_match_over(winning_team: int) -> void:
	if _end_started or m == null:
		return
	_end_started = true
	var rig = m.camera_rig
	if rig == null:
		return
	var nx = m.nexus_units[1 - winning_team]
	if nx == null or not is_instance_valid(nx):
		return
	# League pans from the killing blow to the nexus, then holds while it blows up
	var start: Vector3 = rig.focus
	var goal: Vector3 = nx.global_position
	rig.target = null            # CameraRig only follows a target; with none it keeps whatever focus we set
	rig.locked = true
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_method(func(t: float): rig.focus = start.lerp(goal, t), 0.0, 1.0, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(rig, "target_distance", 15.5, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
