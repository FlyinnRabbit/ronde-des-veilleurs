extends Node2D
# Un Veilleur. Son propriétaire (le joueur local qui le contrôle) décide de sa position ;
# l'hôte décide de sa vie, de son âme et de ses emblèmes.
const Iso = preload("res://scripts/iso.gd")
const DU = preload("res://scripts/draw_util.gd")
const Inputs = preload("res://scripts/inputs.gd")

const COLORS := [Color(0.55, 0.9, 0.95), Color(1.0, 0.7, 0.35), Color(0.78, 0.62, 1.0), Color(0.6, 0.95, 0.55)]
const RADIUS := 13.0
const SOUL_MAX := 99
const SOUL_COST := 33

var game
var slot := 0
var peer := 1
var lidx := 0
var device = "none"
var local := false

var wp := Vector2.ZERO
var target_wp := Vector2.ZERO
var aim := Vector2(0, -1)

# valeurs décidées par l'hôte
var hp := 5
var max_hp := 5
var soul := 0
var down := false
var revive := 0.0
var boons: Array = []
var host_inv_t := 0.0     # hôte : invulnérabilité après un coup reçu
var picked := false       # hôte : a déjà choisi son emblème dans cette salle

# état local
var flags := 0            # 1 ruée, 2 parade, 4 soin, 8 en mouvement
var attack_cd := 0.0
var combo := 0
var combo_t := 0.0
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.ZERO
var parry_t := 0.0
var parry_cd := 0.0
var heal_t := 0.0
var heal_lock := 0.0
var spell_cd := 0.0
var inv_t := 0.0
var knock := Vector2.ZERO
var flash_t := 0.0
var walk_t := 0.0
var swing_t := 0.0
var swing_dir := Vector2(0, -1)
var swing_combo := 0
var prev := {}
var send_t := 0.0
var spike_t := 0.0
var _bot_t := 0.0
var _bot_last := Vector2.ZERO
var _bot_side := false
var _bot_sign := 1.0

func color() -> Color:
	return COLORS[slot % COLORS.size()]

func has(b: String) -> bool:
	return b in boons

func speed() -> float:
	return 190.0 * (1.12 if has("cape") else 1.0)

func reach() -> float:
	return 76.0 * (1.35 if has("aiguille") else 1.0)

func damage() -> int:
	return 1 + (1 if has("force") else 0)

func parry_window() -> float:
	return 0.45 if has("miroir") else 0.25

func heal_time() -> float:
	return 0.5 if has("concentration") else 1.0

func is_inv() -> bool:
	return (flags & 1) != 0 or host_inv_t > 0.0 or down

func is_parrying() -> bool:
	return (flags & 2) != 0

func _ready() -> void:
	target_wp = wp
	position = Iso.to_screen(wp)
	var l := PointLight2D.new()
	l.texture = DU.radial_texture(256)
	l.texture_scale = 2.4
	l.energy = 0.5
	l.color = Color(1.0, 0.9, 0.75)
	l.position = Vector2(0, -20)
	add_child(l)

func place(p: Vector2) -> void:
	wp = p
	target_wp = p
	knock = Vector2.ZERO
	dash_t = 0.0
	heal_t = 0.0
	position = Iso.to_screen(wp)

func _process(delta: float) -> void:
	if game.room == null:
		return
	for k in ["attack_cd", "combo_t", "dash_cd", "parry_t", "parry_cd", "heal_lock", "spell_cd", "inv_t", "flash_t", "swing_t", "host_inv_t", "spike_t"]:
		set(k, maxf(0.0, float(get(k)) - delta))
	if local:
		_control(delta)
	else:
		wp = wp.lerp(target_wp, clampf(delta * 16.0, 0.0, 1.0))
	if (flags & 8) != 0:
		walk_t += delta
	position = Iso.to_screen(wp)
	queue_redraw()

func _just(inp: Dictionary, k: String) -> bool:
	return inp[k] and not prev.get(k, false)

func _control(delta: float) -> void:
	var inp: Dictionary = Inputs.empty()
	if not game.frozen() and not down:
		inp = _bot() if String(device) == "bot" else Inputs.read(device)
	var mv: Vector2 = Iso.dir_to_world(inp["move"]) * minf(1.0, inp["move"].length())
	if inp["mouse"]:
		var d: Vector2 = get_viewport().get_mouse_position() - (get_global_transform_with_canvas().origin + Vector2(0, -20))
		if d.length() > 10.0:
			aim = Iso.dir_to_world(d)
	elif inp["aim"] != Vector2.ZERO:
		aim = Iso.dir_to_world(inp["aim"])
	elif mv != Vector2.ZERO:
		aim = mv.normalized()
	var slow := 1.0
	flags = 0
	# soin : maintenir, coûte de l'âme
	if inp["heal"] and soul >= SOUL_COST and hp < max_hp and dash_t <= 0.0 and heal_lock <= 0.0:
		heal_t += delta
		slow = 0.3
		flags |= 4
		if heal_t >= heal_time():
			heal_t = 0.0
			heal_lock = 0.4
			game.act(slot, "heal", aim, 0)
	else:
		heal_t = 0.0
	if _just(inp, "dash") and dash_cd <= 0.0:
		dash_t = 0.18
		dash_cd = 0.6 * (0.6 if has("cape") else 1.0)
		dash_dir = mv.normalized() if mv != Vector2.ZERO else aim
		Audio.sfx("dash")
	if _just(inp, "parry") and parry_cd <= 0.0:
		parry_t = parry_window()
		parry_cd = 0.7
	if inp["attack"] and attack_cd <= 0.0 and heal_t <= 0.0:
		combo = (combo + 1) % 3 if combo_t > 0.0 else 0
		combo_t = 0.65
		attack_cd = 0.3 * (1.5 if combo == 2 else 1.0) * (1.2 if has("force") else 1.0)
		game.act(slot, "atk", aim, combo)
	if _just(inp, "spell") and soul >= SOUL_COST and spell_cd <= 0.0:
		spell_cd = 0.5
		game.act(slot, "spell", aim, 0)
	prev = inp
	var vel := mv * speed() * slow * (0.55 if swing_t > 0.0 else 1.0)
	if dash_t > 0.0:
		dash_t -= delta
		vel = dash_dir * 560.0
		flags |= 1
	if parry_t > 0.0:
		flags |= 2
	if mv != Vector2.ZERO:
		flags |= 8
	vel += knock
	knock = knock.move_toward(Vector2.ZERO, delta * 900.0)
	wp = game.room.move(wp, vel * delta, RADIUS)
	# on ne traverse pas un boss (sauf pendant la Ruée)
	if dash_t <= 0.0:
		for e in game.enemies.values():
			if e.is_boss() and e.state != "air" and e.state != "spawn":
				var d: Vector2 = wp - e.wp
				var m: float = e.radius() + 6.0
				if d.length() < m:
					wp = game.room.move(wp, (d.normalized() if d.length() > 0.1 else Vector2(0, 1)) * (m - d.length()), RADIUS)
	send_t -= delta
	if send_t <= 0.0:
		send_t = 1.0 / 30.0
		game.send_pstate(self)

# Coups visibles par tout le monde (appelé chez chaque joueur).
func on_act(kind: String, dir: Vector2, c: int) -> void:
	match kind:
		"atk":
			swing_t = 0.2
			swing_dir = dir
			swing_combo = c
			Audio.sfx("slash")
		"spell":
			Audio.sfx("ult", 0.1, -8.0)
		"heal":
			Audio.sfx("heal")
			game.fx("heal", wp, color())

func on_hurt(k: Vector2) -> void:
	flash_t = 0.25
	Audio.sfx("hurt")
	if local:
		knock = k * 280.0
		inv_t = 1.0
		heal_t = 0.0
		game.shake(6.0)

# ------------------------------------------------------------------ pilote automatique (tests)
func _bot() -> Dictionary:
	var inp: Dictionary = Inputs.empty()
	var best = null
	var bd := 1e9
	for e in game.enemies.values():
		var d: float = e.wp.distance_to(wp)
		if d < bd and e.hp > 0:
			bd = d
			best = e
	var goal := wp
	if best != null:
		goal = best.wp
		var to: Vector2 = best.wp - wp
		inp["aim"] = Iso.dir_to_screen(to)
		if bd < reach() * 0.85 + best.radius():
			inp["attack"] = true
		elif soul >= SOUL_COST and bd < 320.0 and hp >= 3:
			inp["spell"] = fmod(game.clock, 0.5) < 0.1
		if bd > reach() * 0.6:
			inp["move"] = Iso.dir_to_screen(to)
		if hp <= 2 and soul >= SOUL_COST and bd > 170.0:
			inp["heal"] = true
			inp["move"] = Vector2.ZERO
	else:
		var ped = game.bot_goal(self)
		if ped != null:
			goal = ped
			if wp.distance_to(goal) > 6.0:
				inp["move"] = Iso.dir_to_screen(goal - wp)
	# coincé contre un pilier : on contourne
	_bot_t -= get_process_delta_time()
	if _bot_t <= 0.0:
		_bot_t = 0.5
		_bot_side = inp["move"] != Vector2.ZERO and wp.distance_to(_bot_last) < 8.0
		if _bot_side:
			_bot_sign = -_bot_sign if randf() < 0.3 else _bot_sign
		_bot_last = wp
	if _bot_side and inp["move"] != Vector2.ZERO:
		inp["move"] = Vector2(-inp["move"].y, inp["move"].x) * _bot_sign
	return inp

# ------------------------------------------------------------------ dessin
func _draw() -> void:
	var col := color()
	var sd: Vector2 = Iso.dir_to_screen(aim)
	var f := 1.0 if sd.x >= 0.0 else -1.0
	DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(17, 7.5), 16), Color(0, 0, 0, 0.4))
	draw_polyline(DU.ellipse(Vector2.ZERO, Vector2(23, 10.5), 28, 0.0, TAU + 0.3), Color(col, 0.6), 2.0)
	if down:
		_draw_down(col)
		return
	var bob := sin(walk_t * 14.0) * 1.5 if (flags & 8) != 0 else 0.0
	var o := Vector2(0, bob)
	var a := 1.0
	if (local and inv_t > 0.0) or host_inv_t > 0.0:
		a = 0.45 + 0.4 * absf(sin(game.clock * 30.0))
	if (flags & 1) != 0:
		var sdd: Vector2 = Iso.dir_to_screen(dash_dir if local else aim)
		for i in 3:
			DU.flat(self, DU.ellipse(-sdd * (14.0 + i * 12.0) + Vector2(0, -18), Vector2(11, 17), 12), Color(col, 0.22 - i * 0.06))
	var cloak := Color(0.3, 0.24, 0.42, a)
	if flash_t > 0.0:
		cloak = Color(1, 1, 1, a)
	DU.poly(self, PackedVector2Array([o + Vector2(-14, 0), o + Vector2(-10, -26), o + Vector2(0, -34), o + Vector2(10, -26), o + Vector2(14, 0), o + Vector2(6, -3), o + Vector2(0, 1), o + Vector2(-6, -3)]), cloak)
	DU.poly(self, PackedVector2Array([o + Vector2(-11, -24), o + Vector2(-2 * f, -46), o + Vector2(11, -24), o + Vector2(8, -18), o + Vector2(-8, -18)]), cloak.lightened(0.08))
	draw_circle(o + Vector2(4 * f, -27), 6.5, Color(0.06, 0.05, 0.1, a))
	DU.glow(self, o + Vector2(5 * f, -27), 9.0, Color(1.0, 0.95, 0.6), 0.5 * a)
	draw_circle(o + Vector2(5 * f, -27), 3.2, Color(1.0, 0.97, 0.7, a))
	draw_polyline(PackedVector2Array([o + Vector2(-6 * f, -20), o + Vector2(-14 * f, -18), o + Vector2(-20 * f, -12 + bob), o + Vector2(-26 * f, -14 - bob)]), Color(col, a), 3.0)
	# aiguille, pointée vers la visée
	var hand := o + Vector2(8 * f, -14)
	draw_line(hand, hand + sd * 24.0, Color(0.9, 0.93, 1.0, a), 2.5)
	# coup d'aiguille
	if swing_t > 0.0:
		var k := swing_t / 0.2
		var ssd: Vector2 = Iso.dir_to_screen(swing_dir)
		var ang := ssd.angle()
		var r := reach() * 0.78 * (1.25 if swing_combo == 2 else 1.0)
		var half := 1.05 if swing_combo < 2 else 1.6
		var sweep := (1.0 - k) * half * 2.0 * (1.0 if swing_combo != 1 else -1.0)
		var a0 := ang - half * (1.0 if swing_combo != 1 else -1.0)
		draw_set_transform(Vector2(0, -18), 0.0, Vector2(1.0, 0.62))
		for i in 3:
			draw_arc(Vector2.ZERO, r - i * 5.0, a0, a0 + sweep + 0.01, 18, Color(1.0, 0.96, 0.82, (0.75 - i * 0.2) * k), 8.0 - i * 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if (flags & 2) != 0:
		draw_arc(Vector2(0, -20) + sd * 6.0, 24.0, sd.angle() - 1.1, sd.angle() + 1.1, 14, Color(0.8, 0.95, 1.0, 0.9), 4.0)
	if (flags & 4) != 0:
		var hk := clampf(heal_t / heal_time(), 0.0, 1.0) if local else 0.5 + 0.5 * sin(game.clock * 8.0)
		DU.glow(self, Vector2(0, -20), 30.0, Color(0.8, 0.95, 1.0), 0.35)
		draw_arc(Vector2(0, -20), 26.0, -PI / 2.0, -PI / 2.0 + TAU * hk, 24, Color(0.85, 0.97, 1.0), 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(-9, -54), "J%d" % (slot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

func _draw_down(col: Color) -> void:
	var cloak := Color(0.22, 0.18, 0.3)
	DU.poly(self, PackedVector2Array([Vector2(-20, -2), Vector2(-12, -12), Vector2(10, -12), Vector2(22, -4), Vector2(14, 3), Vector2(-14, 3)]), cloak)
	draw_circle(Vector2(14, -8), 5.0, Color(0.06, 0.05, 0.1))
	draw_arc(Vector2(0, -6), 30.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(revive, 0.0, 1.0), 28, col, 4.0)
	draw_arc(Vector2(0, -6), 30.0, 0.0, TAU, 28, Color(col, 0.25), 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(-34, -44), "À terre !", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.5, 0.45))
