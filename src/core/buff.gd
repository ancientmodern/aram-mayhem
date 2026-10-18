class_name Buff
extends Effect
## Timed effect on a unit: stat changes, crowd control, damage over time, etc.

enum CC {
	NONE = 0,
	STUN = 1, ROOT = 2, SILENCE = 4, DISARM = 8, AIRBORNE = 16, CHARM = 32, FEAR = 64,
	TAUNT = 128, SUPPRESS = 256, SLEEP = 512, GROUNDED = 1024, BLIND = 2048, POLYMORPH = 4096,
	STASIS = 8192, UNTARGETABLE = 16384, INVULNERABLE = 32768, UNSTOPPABLE = 65536,
	GHOSTED = 131072, CAMOUFLAGE = 262144, NEARSIGHT = 524288,
}
const HARD_CC := CC.STUN | CC.ROOT | CC.SILENCE | CC.DISARM | CC.AIRBORNE | CC.CHARM | CC.FEAR \
		| CC.TAUNT | CC.SUPPRESS | CC.SLEEP | CC.GROUNDED | CC.BLIND | CC.POLYMORPH
const IMMOBILIZE := CC.STUN | CC.ROOT | CC.AIRBORNE | CC.CHARM | CC.FEAR | CC.TAUNT | CC.SUPPRESS | CC.SLEEP
const BLOCK_MOVE := CC.STUN | CC.ROOT | CC.AIRBORNE | CC.SUPPRESS | CC.SLEEP | CC.STASIS
const BLOCK_ATTACK := CC.STUN | CC.DISARM | CC.AIRBORNE | CC.SUPPRESS | CC.SLEEP | CC.STASIS \
		| CC.CHARM | CC.FEAR | CC.POLYMORPH
const BLOCK_CAST := CC.STUN | CC.SILENCE | CC.AIRBORNE | CC.SUPPRESS | CC.SLEEP | CC.STASIS \
		| CC.CHARM | CC.FEAR | CC.TAUNT | CC.POLYMORPH
const FORCED_MOVE := CC.CHARM | CC.FEAR | CC.TAUNT
const TENACITY_AFFECTED := CC.STUN | CC.ROOT | CC.SILENCE | CC.DISARM | CC.CHARM | CC.FEAR \
		| CC.TAUNT | CC.SLEEP | CC.BLIND | CC.POLYMORPH | CC.GROUNDED | CC.NEARSIGHT

enum Stack { REFRESH, ADD_STACK, INDEPENDENT, KEEP_LONGEST }

var duration := 1.0
var remaining := 1.0
var stacks := 1
var max_stacks := 1
var stack_mode := Stack.REFRESH
var cc := 0                 ## CC flags
var slow_amount := 0.0      ## 0..1 movement slow (strongest slow applies)
var slow_decays := false    ## slow decays linearly over duration
var is_debuff := false
var cleansable := true
var tick_interval := 0.0
var _tick_acc := 0.0
var stats_per_stack := {}   ## stat mods multiplied by stacks
var forced_dest := Vector3.ZERO   ## destination for charm/taunt/fear movement
var forced_target = null          ## unit to walk toward (charm/taunt) or away from (fear)
var permanent := false
var show_timer := true
var vfx: Node3D = null      ## attached visual, freed on removal
var on_expire := Callable() ## optional callback(buff)
var on_interval := Callable() ## optional callback(buff) every tick_interval


func _init(p_id: String = "", p_duration: float = 1.0) -> void:
	id = p_id
	display_name = p_id
	duration = p_duration
	remaining = p_duration


func get_stat_mods() -> Dictionary:
	if stats_per_stack.is_empty():
		return stats
	var d := stats.duplicate()
	for k in stats_per_stack:
		d[k] = d.get(k, 0.0) + stats_per_stack[k] * stacks
	return d


func current_slow() -> float:
	if slow_decays and duration > 0.0:
		return slow_amount * clampf(remaining / duration, 0.0, 1.0)
	return slow_amount


## Called by the unit each tick. Returns false when expired.
func tick(unit, dt: float) -> bool:
	on_tick(unit, dt)
	if tick_interval > 0.0:
		_tick_acc += dt
		while _tick_acc >= tick_interval:
			_tick_acc -= tick_interval
			on_interval_tick(unit)
			if on_interval.is_valid():
				on_interval.call(self)
	if permanent:
		return not removed
	remaining -= dt
	if remaining <= 0.0:
		return false
	return not removed


func on_interval_tick(_unit) -> void:
	pass


func expire() -> void:
	removed = true


func on_removed(_unit) -> void:
	if on_expire.is_valid():
		on_expire.call(self)
	if vfx != null and is_instance_valid(vfx):
		if vfx.has_method("stop"):
			vfx.stop()
		else:
			vfx.queue_free()
		vfx = null
