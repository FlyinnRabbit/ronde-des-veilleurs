extends Node2D
# Un ennemi. L'hôte fait tourner son comportement ; les autres joueurs reçoivent son état
# (position, vie, état, minuteur) et se contentent de le dessiner.
const Iso = preload("res://scripts/iso.gd")
const DU = preload("res://scripts/draw_util.gd")

const DEF := {
	"rampant": {"hp": 3, "r": 16.0, "speed": 90.0, "shards": 2},
	"volant": {"hp": 2, "r": 13.0, "speed": 125.0, "shards": 2, "fly": true},
	"cracheur": {"hp": 3, "r": 15.0, "speed": 58.0, "shards": 3},
	"garde": {"hp": 5, "r": 16.0, "speed": 68.0, "shards": 4},
	"gardien": {"hp": 55, "r": 34.0, "speed": 76.0, "shards": 60, "boss": true},
}

var game
var id := 0
var kind := "rampant"
var host := false
var wp := Vector2.ZERO
var target_wp := Vector2.ZERO
var hp := 3
var max_hp := 3
var state := "spawn"
var t := 0.7
var face := Vector2(0, 1)
var tgt := Vector2.ZERO       # cible d'une attaque (charge, bond)
var stun_t := 0.0
var flash_t := 0.0
var anim_t := 0.0
var touch_cd := 0.0
var phase2 := false
var summoned := false
var src := Vector2.ZERO

func radius() -> float:
	return float(DEF[kind]["r"])

func is_boss() -> bool:
	return DEF[kind].has("boss")

func flying() -> bool:
	return DEF[kind].has("fly")

func setup(k: String, p: Vector2, hp_mult: float) -> void:
	kind = k
	wp = p
	target_wp = p
	max_hp = maxi(1, roundi(float(DEF[k]["hp"]) * hp_mult))
	hp = max_hp
	position = Iso.to_screen(wp)

func _process(delta: float) -> void:
	if game.room == null:
		return
	anim_t += delta
	flash_t = maxf(0.0, flash_t - delta)
	if host:
		touch_cd = maxf(0.0, touch_cd - delta)
		if not game.frozen():
			_tick(delta)
	else:
		wp = wp.lerp(target_wp, clampf(delta * 14.0, 0.0, 1.0))
		t = maxf(0.0, t - delta)
		stun_t = maxf(0.0, stun_t - delta)
	position = Iso.to_screen(wp)
	queue_redraw()

func _go(dir: Vector2, speed: float, delta: float) -> void:
	var np: Vector2 = game.room.move(wp, dir * speed * delta, radius(), flying())
	if state in ["walk", "back"]:
		# on ne marche pas « dans » un Veilleur : on s'arrête au contact
		for p in game.players.values():
			if not p.down and np.distance_to(p.wp) < radius() + 10.0 and np.distance_to(p.wp) < wp.distance_to(p.wp):
				return
	wp = np

func _touch(dmg: int) -> void:
	if touch_cd > 0.0:
		return
	for p in game.players.values():
		if p.down:
			continue
		if p.wp.distance_to(wp) < radius() + 13.0:
			var res: String = game.hurt_player(p, dmg, wp, true)
			if res == "parried":
				stun_t = 1.0 if is_boss() else 1.6
				state = "walk"
				t = 0.6
				touch_cd = 0.5
				return
			if res == "hit":
				touch_cd = 0.6

func _tick(delta: float) -> void:
	if state == "spawn":
		t -= delta
		if t <= 0.0:
			state = "walk"
			t = randf_range(0.6, 1.4)
		return
	if stun_t > 0.0:
		stun_t -= delta
		return
	var p = game.nearest_player(wp)
	if p == null:
		return
	var to: Vector2 = p.wp - wp
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var sp: float = float(DEF[kind]["speed"]) * game.speed_mult()
	match kind:
		"rampant":
			if state == "back":
				t -= delta
				_go(-dir, sp * 0.8, delta)
				if t <= 0.0:
					state = "walk"
			else:
				face = dir
				_go(dir, sp, delta)
				var before := touch_cd
				_touch(1)
				if touch_cd > before:
					state = "back"
					t = 0.45
		"volant":
			match state:
				"walk":
					face = dir
					if dist > 210.0:
						_go(dir, sp, delta)
					elif dist < 130.0:
						_go(-dir, sp, delta)
					else:
						_go(Vector2(-dir.y, dir.x), sp * 0.6, delta)
					t -= delta
					if t <= 0.0 and dist < 260.0:
						state = "windup"
						t = 0.55
				"windup":
					face = dir
					t -= delta
					if t <= 0.0:
						state = "dive"
						t = 0.45
				"dive":
					_go(face, 470.0, delta)
					_touch(1)
					t -= delta
					if t <= 0.0:
						state = "rest"
						t = 0.9
				"rest":
					t -= delta
					if t <= 0.0:
						state = "walk"
						t = randf_range(0.8, 1.6)
		"cracheur":
			match state:
				"walk":
					face = dir
					if dist > 300.0:
						_go(dir, sp, delta)
					elif dist < 200.0:
						_go(-dir, sp, delta)
					t -= delta
					if t <= 0.0:
						state = "windup"
						t = 0.45
				"windup":
					face = dir
					t -= delta
					if t <= 0.0:
						game.spawn_shot("spore", wp + dir * 18.0, dir * 250.0, -1)
						state = "walk"
						t = randf_range(1.9, 2.6)
			_touch(1)
		"garde":
			match state:
				"walk":
					face = dir
					_go(dir, sp, delta)
					if dist < 80.0:
						state = "windup"
						t = 0.5
				"windup":
					t -= delta
					if t <= 0.0:
						state = "bash"
						t = 0.22
				"bash":
					_go(face, 400.0, delta)
					_touch(1)
					t -= delta
					if t <= 0.0:
						state = "rest"
						t = 0.9
				"rest":
					t -= delta
					if t <= 0.0:
						state = "walk"
		"gardien":
			_boss(delta, p, dir, dist, sp)

func _boss(delta: float, p, dir: Vector2, dist: float, sp: float) -> void:
	if not phase2 and hp * 2 <= max_hp:
		phase2 = true
		game.fx_all("roar", wp, Color(1.0, 0.5, 0.3))
		game.shake_all(8.0)
	var q := 0.75 if phase2 else 1.0
	match state:
		"walk":
			face = dir
			_go(dir, sp * (1.25 if phase2 else 1.0), delta)
			_touch(1)
			t -= delta
			if t <= 0.0:
				if phase2 and not summoned:
					summoned = true
					game.spawn_enemy("rampant", wp + Vector2(70, 0))
					game.spawn_enemy("rampant", wp + Vector2(-70, 0))
				if dist > 150.0 and randf() < 0.55:
					state = "charge_w"
					t = 0.75 * q
				else:
					state = "slam_w"
					t = 0.5 * q
					tgt = p.wp
		"charge_w":
			face = dir
			tgt = wp + dir * 600.0
			t -= delta
			if t <= 0.0:
				state = "charge"
				t = 1.2
		"charge":
			var before := wp
			_go(face, 540.0, delta)
			_touch(2 if phase2 else 1)
			t -= delta
			if wp.distance_to(before) < 540.0 * delta * 0.4 or t <= 0.0:
				if t > 0.0:
					game.shake_all(7.0)
					game.fx_all("dust", wp, Color(0.7, 0.75, 0.9))
				state = "rest"
				t = 1.2 * q
		"slam_w":
			t -= delta
			if t <= 0.0:
				state = "air"
				t = 0.7
				src = wp
		"air":
			t -= delta
			var k := 1.0 - clampf(t / 0.7, 0.0, 1.0)
			var dest := src.lerp(tgt, k)
			wp = game.room.move(wp, dest - wp, radius(), true)
			if t <= 0.0:
				game.spawn_shot("ring", wp, Vector2.ZERO, -1)
				if phase2:
					game.spawn_shot("ring2", wp, Vector2.ZERO, -1)
				game.shake_all(9.0)
				Audio.sfx("kill", 0.05, -2.0)
				_touch(1)
				state = "rest"
				t = 0.9 * q
		"rest":
			t -= delta
			if t <= 0.0:
				state = "walk"
				t = randf_range(1.0, 1.8) * q

# Renvoie vrai si le coup a porté.
func take_hit(dmg: int, from: Vector2) -> bool:
	if state == "spawn" or state == "air" or hp <= 0:
		return false
	var d := (from - wp).normalized()
	if kind == "garde" and stun_t <= 0.0 and state in ["walk", "windup"] and face.dot(d) > 0.3:
		game.ev_all("block", [wp.x, wp.y])
		return false
	hp -= dmg
	flash_t = 0.12
	if not is_boss():
		wp = game.room.move(wp, -d * 20.0, radius(), flying())
		if state == "windup" and kind != "garde":
			state = "walk"
			t = 0.5
	return true

# ------------------------------------------------------------------ dessin
func telegraph() -> bool:
	return state in ["windup", "charge_w", "slam_w"]

func _draw() -> void:
	var r := radius()
	if state == "spawn":
		var k := 1.0 - clampf(t / 0.7, 0.0, 1.0)
		draw_polyline(DU.ellipse(Vector2.ZERO, Vector2(r * 1.5, r * 0.7) * (1.4 - k * 0.4), 24, 0.0, TAU + 0.3), Color(1.0, 0.4, 0.35, 0.8), 2.0)
		DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(r * 1.5, r * 0.7) * k, 20), Color(1.0, 0.35, 0.3, 0.25))
		return
	var sf: Vector2 = Iso.dir_to_screen(face)
	var f := 1.0 if sf.x >= 0.0 else -1.0
	var white := flash_t > 0.0
	DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(r * 1.15, r * 0.5), 16), Color(0, 0, 0, 0.4))
	match kind:
		"rampant":
			var c := Color(1, 1, 1) if white else Color(0.32, 0.42, 0.52)
			for k in 3:
				var sw := sin(anim_t * 14.0 + k * 2.0) * 3.0
				draw_line(Vector2(-10 + k * 9, -6), Vector2(-14 + k * 11 + sw, 2), Color(0.12, 0.12, 0.16), 2.5)
			DU.poly(self, DU.ellipse(Vector2(0, -11), Vector2(18, 12), 18), c)
			draw_arc(Vector2(0, -11), 12.0, PI * 1.1, PI * 1.9, 10, Color(1, 1, 1, 0.25), 2.0)
			draw_circle(Vector2(11 * f, -9), 2.5, Color(1.0, 0.85, 0.5))
		"volant":
			var b := Vector2(0, -44 + sin(anim_t * 5.0) * 3.0)
			if state == "dive":
				b.y = -22.0
			var wy := sin(anim_t * 40.0) * 5.0
			DU.flat(self, DU.ellipse(b + Vector2(-13, -8 + wy), Vector2(13, 6), 12), Color(0.8, 0.9, 1.0, 0.45))
			DU.flat(self, DU.ellipse(b + Vector2(13, -8 - wy), Vector2(13, 6), 12), Color(0.8, 0.9, 1.0, 0.45))
			DU.ball(self, b, 10.0, Color(1, 1, 1) if white else Color(0.45, 0.35, 0.55))
			draw_circle(b + Vector2(4 * f, -1), 2.5, Color(1.0, 0.4, 0.35))
		"cracheur":
			var s := 1.0 + (0.18 * (1.0 - t / 0.45) if state == "windup" else 0.0)
			DU.poly(self, PackedVector2Array([Vector2(-7, 0), Vector2(-5, -14), Vector2(5, -14), Vector2(7, 0)]), Color(0.3, 0.4, 0.3))
			DU.ball(self, Vector2(0, -24), 15.0 * s, Color(1, 1, 1) if white else Color(0.4, 0.62, 0.38))
			draw_circle(Vector2(0, -22) + sf * 8.0, 5.0, Color(0.08, 0.12, 0.08))
		"garde":
			var c2 := Color(1, 1, 1) if white else Color(0.42, 0.4, 0.46)
			DU.poly(self, PackedVector2Array([Vector2(-12, 0), Vector2(-10, -30), Vector2(10, -30), Vector2(12, 0)]), c2)
			DU.ball(self, Vector2(0, -36), 9.0, c2.lightened(0.1))
			var sh := sf * 12.0 + Vector2(0, -18)
			DU.poly(self, PackedVector2Array([sh + Vector2(-8, -13), sh + Vector2(8, -13), sh + Vector2(8, 8), sh + Vector2(0, 14), sh + Vector2(-8, 8)]), Color(0.6, 0.5, 0.3))
			draw_line(sh + Vector2(0, -9), sh + Vector2(0, 8), Color(0.9, 0.8, 0.5), 2.0)
		"gardien":
			_draw_boss(sf, f, white)
	if stun_t > 0.0:
		for k in 3:
			var a := anim_t * 6.0 + k * TAU / 3.0
			draw_circle(Vector2(cos(a) * 14.0, -r * 2.2 - 18.0 + sin(a) * 4.0), 2.5, Color(1.0, 0.9, 0.4))
	elif telegraph():
		draw_string(ThemeDB.fallback_font, Vector2(-5, -r * 2.2 - 22.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 24 if is_boss() else 20, Color(1.0, 0.85, 0.3))
	if hp < max_hp and not is_boss():
		var w := 30.0
		draw_rect(Rect2(-w / 2.0, -r * 2.2 - 14.0, w, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2.0, -r * 2.2 - 14.0, w * clampf(float(hp) / max_hp, 0.0, 1.0), 4), Color(0.9, 0.3, 0.3))

func _draw_boss(sf: Vector2, f: float, white: bool) -> void:
	# annonces au sol
	if state == "charge_w":
		var e: Vector2 = Iso.to_screen(tgt - wp)
		draw_line(Vector2.ZERO, e, Color(1.0, 0.35, 0.3, 0.35), 26.0)
		draw_line(Vector2.ZERO, e, Color(1.0, 0.5, 0.4, 0.8), 2.0)
	if state in ["slam_w", "air"]:
		var c: Vector2 = Iso.to_screen(tgt - wp)
		draw_polyline(DU.ellipse(c, Vector2(70, 32), 28, 0.0, TAU + 0.3), Color(1.0, 0.4, 0.35, 0.9), 2.5)
		DU.flat(self, DU.ellipse(c, Vector2(70, 32), 24), Color(1.0, 0.35, 0.3, 0.18))
	var lift := 0.0
	if state == "air":
		lift = -sin((1.0 - clampf(t / 0.7, 0.0, 1.0)) * PI) * 120.0
	var o := Vector2(0, lift)
	var shell := Color(1, 1, 1) if white else (Color(0.5, 0.3, 0.3) if phase2 else Color(0.3, 0.36, 0.5))
	for k in 4:
		var sw := sin(anim_t * 10.0 + k * 1.7) * 4.0 if state in ["walk", "charge"] else 0.0
		draw_line(o + Vector2(-24 + k * 16, -10), o + Vector2(-32 + k * 21 + sw, 4), Color(0.1, 0.1, 0.14), 5.0)
	DU.poly(self, DU.ellipse(o + Vector2(0, -30), Vector2(42, 30), 24), shell)
	draw_line(o + Vector2(0, -60), o + Vector2(0, -4), Color(0, 0, 0, 0.3), 2.0)
	draw_arc(o + Vector2(0, -30), 30.0, PI * 1.1, PI * 1.9, 14, Color(1, 1, 1, 0.22), 3.0)
	var hd := o + Vector2(0, -26) + sf * 34.0
	DU.ball(self, hd, 16.0, shell.darkened(0.15))
	DU.flat(self, PackedVector2Array([hd + sf * 10.0 + Vector2(-5, -6), hd + sf * 34.0 + Vector2(0, -16), hd + sf * 10.0 + Vector2(5, 2)]), Color(0.85, 0.85, 0.9))
	var eye := Color(1.0, 0.4, 0.3) if phase2 else Color(1.0, 0.85, 0.5)
	DU.glow(self, hd + Vector2(5 * f, -4), 9.0, eye, 0.5)
	draw_circle(hd + Vector2(5 * f, -4), 3.5, eye)
