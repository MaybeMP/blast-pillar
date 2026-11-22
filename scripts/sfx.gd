extends Node
## Plays the game's 8-bit sounds. Replace any file in res://sounds/ to change a sound.

const NAMES := ["explode", "explode_big", "land", "drop", "gem", "gem_rare", "buy", "click", "error", "crack", "portal", "unlock", "acid", "freeze"]

var enabled := true
var players := {}
var last_play := {}


func _ready() -> void:
	for n in NAMES:
		var path := "res://sounds/%s.wav" % n
		if not ResourceLoader.exists(path):
			continue
		var p := AudioStreamPlayer.new()
		p.stream = load(path)
		p.max_polyphony = 6
		add_child(p)
		players[n] = p


## min_gap stops the same sound stacking up when lots happen at once.
func play(name: String, pitch := 1.0, volume_db := 0.0, min_gap := 0.03) -> void:
	if not enabled or not players.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_play.get(name, -1.0)) < min_gap:
		return
	last_play[name] = now
	var p: AudioStreamPlayer = players[name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()
