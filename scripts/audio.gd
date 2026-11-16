extends Node
# Autoload « Audio » : bruitages et musique (repris de Lanterne des Profondeurs).
var _players: Array = []
var _music: AudioStreamPlayer
var _cur := ""
var muted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	muted = DisplayServer.get_name() == "headless"
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -10.0
	add_child(_music)

func sfx(n: String, pitch_var := 0.08, vol_db := -4.0) -> void:
	if muted:
		return
	var path := "res://sfx/%s.wav" % n
	if not ResourceLoader.exists(path):
		return
	for p in _players:
		if not p.playing:
			p.stream = load(path)
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.volume_db = vol_db
			p.play()
			return

func music(n: String) -> void:
	if muted or n == _cur:
		return
	_cur = n
	var path := "res://music/%s.ogg" % n
	if n == "" or not ResourceLoader.exists(path):
		_music.stop()
		return
	var s = load(path)
	if s is AudioStreamOggVorbis:
		s.loop = true
	_music.stream = s
	_music.play()
