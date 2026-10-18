class_name Prof
extends RefCounted
## Tiny frame profiler: Prof.t0() / Prof.add("section", t0) accumulate microseconds per section.
## Disabled (near-zero cost) unless Prof.enabled is set (perf harness).

static var enabled := false
static var acc := {}       ## section -> total usec since last report
static var peak := {}      ## section -> worst single-frame usec since last report
static var frame := {}     ## section -> usec this frame


static func t0() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func add(section: String, start: int) -> void:
	if not enabled:
		return
	var d := Time.get_ticks_usec() - start
	acc[section] = acc.get(section, 0) + d
	frame[section] = frame.get(section, 0) + d


## Call once per frame (end of frame) to fold per-frame totals into peaks.
static func end_frame() -> void:
	for k in frame:
		if frame[k] > peak.get(k, 0):
			peak[k] = frame[k]
	frame.clear()


static func report(frames: int) -> String:
	var keys := acc.keys()
	keys.sort_custom(func(a, b): return acc[a] > acc[b])
	var parts := []
	for k in keys:
		parts.append("%s=%.2f/%.1f" % [k, acc[k] / 1000.0 / maxf(frames, 1), peak.get(k, 0) / 1000.0])
	acc.clear()
	peak.clear()
	return " ".join(parts)
