extends CanvasLayer
# Affichage en jeu : un panneau par Veilleur, salle en cours, éclats, barre du boss, messages.
const DU = preload("res://scripts/draw_util.gd")
var game
var view: Control

class View extends Control:
	var hud
	func _draw() -> void:
		hud.draw_hud(self)

func _ready() -> void:
	layer = 5
	view = View.new()
	view.hud = self
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)

func _process(_d: float) -> void:
	view.queue_redraw()

func _text(v: Control, pos: Vector2, s: String, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	v.draw_string_outline(f, pos, s, align, width, size, 4, Color(0, 0, 0, 0.7))
	v.draw_string(f, pos, s, align, width, size, col)

func draw_hud(v: Control) -> void:
	if game.mode == "menu" or game.room == null:
		return
	var sz := v.size
	var slots: Array = game.players.keys()
	slots.sort()
	var i := 0
	for s in slots:
		_panel(v, Vector2(22, 22 + i * 64.0), game.players[s])
		i += 1
	# titre de la salle
	var title := "Le Sanctuaire — salon"
	var sub := "En attente du départ"
	if game.mode == "run":
		title = "Palier 1 — salle %d / %d" % [game.room_index + 1, game.RUN.size()]
		sub = {"combat": "Les Profondeurs", "rest": "Halte de la Lanterne", "boss": "Le Gardien du Puits"}.get(game.room_kind, "")
	_text(v, Vector2(0, 40), title, 22, Color(1.0, 0.88, 0.6), sz.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text(v, Vector2(0, 62), sub, 14, Color(0.6, 0.7, 0.85), sz.x, HORIZONTAL_ALIGNMENT_CENTER)
	# éclats (partagés)
	var g := Vector2(sz.x - 120, 44)
	DU.flat(v, PackedVector2Array([g + Vector2(0, -12), g + Vector2(9, 0), g + Vector2(0, 12), g + Vector2(-9, 0)]), Color(0.55, 0.8, 1.0))
	_text(v, g + Vector2(16, 7), str(game.shards), 20, Color(0.9, 0.95, 1.0))
	# boss
	for e in game.enemies.values():
		if e.is_boss():
			var w := 520.0
			var o := Vector2((sz.x - w) / 2.0, sz.y - 86)
			v.draw_rect(Rect2(o - Vector2(4, 4), Vector2(w + 8, 22)), Color(0.08, 0.06, 0.05, 0.9))
			v.draw_rect(Rect2(o, Vector2(w * clampf(float(e.hp) / e.max_hp, 0.0, 1.0), 14)), Color(0.85, 0.3, 0.25))
			v.draw_rect(Rect2(o - Vector2(4, 4), Vector2(w + 8, 22)), Color(0.85, 0.7, 0.35), false, 2.0)
			_text(v, Vector2(0, o.y - 10), "Le Gardien du Puits", 16, Color(1.0, 0.88, 0.6), sz.x, HORIZONTAL_ALIGNMENT_CENTER)
	# consignes
	var hint := ""
	var any_down := false
	for p in game.players.values():
		if p.down:
			any_down = true
	if game.mode == "lobby":
		hint = "Clavier : ZQSD bouger · clic gauche frapper · Espace ruée · clic droit parade · E sort d'âme · F soin (maintenir)\nManette : stick gauche bouger · stick droit viser · X frapper · A ruée · LB parade · RB sort · B soin · Start : rejoindre"
	elif any_down and game.phase != "over":
		hint = "Un Veilleur est à terre : restez près de lui pour le relever"
	elif game.door_open and game.pedestals.size() > 0 and _local_unpicked():
		hint = "Choisissez un emblème : restez dessus un instant — puis rejoignez le portail"
	elif game.door_open:
		hint = "Portail ouvert : tous les Veilleurs devant le portail (%d / %d)" % [game.door_count.x, game.door_count.y]
	if hint != "":
		var lines := hint.split("\n")
		for k in lines.size():
			_text(v, Vector2(0, sz.y - 34 + (k - lines.size() + 1) * 20.0), lines[k], 14, Color(0.82, 0.86, 0.95), sz.x, HORIZONTAL_ALIGNMENT_CENTER)
	if game.banner_t > 0.0:
		var a := clampf(game.banner_t, 0.0, 1.0)
		_text(v, Vector2(0, sz.y * 0.3), game.banner, 30, Color(1.0, 0.9, 0.65, a), sz.x, HORIZONTAL_ALIGNMENT_CENTER)

func _local_unpicked() -> bool:
	for p in game.players.values():
		if p.local and not p.picked and not p.down:
			return true
	return false

func _panel(v: Control, o: Vector2, p) -> void:
	var col: Color = p.color()
	v.draw_rect(Rect2(o, Vector2(210, 54)), Color(0.1, 0.075, 0.06, 0.88))
	v.draw_rect(Rect2(o, Vector2(210, 54)), Color(col, 0.85), false, 2.0)
	# fiole d'âme
	var vc := o + Vector2(28, 27)
	v.draw_circle(vc, 19.0, Color(0.05, 0.06, 0.1))
	var k := clampf(float(p.soul) / p.SOUL_MAX, 0.0, 1.0)
	if k > 0.02:
		DU.flat(v, DU.ellipse(vc, Vector2(17, 17), 22, PI * (0.5 - k), PI * (0.5 + k)), Color(0.75, 0.9, 1.0) if p.soul >= p.SOUL_COST else Color(0.45, 0.55, 0.7))
	v.draw_arc(vc, 19.0, 0.0, TAU, 28, Color(0.8, 0.65, 0.3), 2.5)
	var f := ThemeDB.fallback_font
	var tag := "J%d" % (p.slot + 1)
	if p.local:
		tag += " (vous)"
	if p.down:
		tag += " — à terre"
	v.draw_string(f, o + Vector2(56, 19), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.5, 0.45) if p.down else col)
	for m in p.max_hp:
		var mc := o + Vector2(62 + m * 20, 37)
		var on: bool = m < p.hp
		DU.flat(v, PackedVector2Array([mc + Vector2(-7, -8), mc + Vector2(7, -8), mc + Vector2(7, 2), mc + Vector2(0, 9), mc + Vector2(-7, 2)]), Color(0.9, 0.92, 0.96) if on else Color(0.2, 0.22, 0.3))
	# emblèmes obtenus
	for b in p.boons.size():
		var bc := o + Vector2(218 + b * 16, 27)
		DU.flat(v, DU.diamond(bc, Vector2(6, 8)), game.BOONS[p.boons[b]]["col"])
