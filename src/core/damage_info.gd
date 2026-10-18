class_name DamageInfo
extends RefCounted
## One instance of damage, passed through the effect hooks.

var source = null          ## Unit dealing damage (can be null/environment)
var target = null          ## Unit receiving damage
var amount := 0.0          ## pre-mitigation amount (modifiable by pre hooks)
var type := 0              ## G.DmgType
var final := 0.0           ## health actually lost (after shields)
var absorbed := 0.0        ## absorbed by shields
var mitigated := 0.0       ## post-mitigation total before shields
var is_attack := false     ## basic attack damage
var is_crit := false
var is_spell := false      ## ability damage
var is_aoe := false
var is_dot := false
var is_proc := false       ## item / augment / on-hit proc
var is_pet := false
var is_reflect := false
var is_true_execute := false
var can_crit := false      ## ability damage that may crit (Jeweled Gauntlet etc.)
var no_vamp := false
var no_hooks := false      ## skip on-damage hooks (prevents infinite proc loops)
var ability = null         ## Ability that caused it, if any
var tag := ""              ## free-form tag for effects/vfx ("q", "burn", ...)
var cancelled := false
var killed := false
var show_number := true
var mult := 1.0            ## multiplicative modifier accumulated by hooks
var flat_bonus := 0.0      ## additive bonus accumulated by hooks (pre-mitigation)


func _init(p_source = null, p_target = null, p_amount: float = 0.0, p_type: int = 0) -> void:
	source = p_source
	target = p_target
	amount = p_amount
	type = p_type
