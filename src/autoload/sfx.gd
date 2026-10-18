extends Node
## Sound effects manager (autoload `Sfx`).

var players: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)


func play(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	for p in players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db + linear_to_db(G.settings.sfx_volume * G.settings.master_volume)
			p.pitch_scale = pitch
			p.play()
			return
