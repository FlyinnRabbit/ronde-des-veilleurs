extends Node2D
# Projectiles et ondes de choc. L'hôte décide des dégâts ; tout le monde fait avancer le tir.
const Iso = preload("res://scripts/iso.gd")
const DU = preload("res://scripts/draw_util.gd")

var game
var id := 0
var kind := "spore"     # spore / spore_r (renvoyée) / soul (lame d'âme) / ring, ring2 (ondes du boss)
var host := false
var wp := Vector2.ZERO
var vel := Vector2.ZERO
var r := 0.0
var life := 4.0
var owner_slot := -1
var hit := {}
var dead := false
var t := 0.0

func _process(delta: float) -> void:
	if game.room == null:
		return
	t += delta
	visible = not dead
	if game.frozen() or dead:
		return
	life -= delta
	match kind:
		"ring", "ring2":
			var sp := 300.0 if kind == "ring" else 190.0
			r += sp * delta
			if r > 330.0:
				dead = true
			if host:
				for p in game.players.values():
					if p.down or hit.has(p.slot):
						continue
					if absf(p.wp.distance_to(wp) - r) < 18.0:
						if game.hurt_player(p, 1, wp, false) != "miss":
							hit[p.slot] = true
		_:
			wp += vel * delta
			if game.room.blocked_at(wp) or life <= 0.0:
				dead = true
			elif host:
				_collide()
	position = Iso.to_screen(wp)
	queue_redraw()

func _collide() -> void:
	match kind:
		"spore":
			for p in game.players.values():
				if p.down:
					continue
				if p.wp.distance_to(wp) < 17.0:
					var res: String = game.hurt_player(p, 1, wp, true)
					if res == "parried":
						kind = "spore_r"
						vel = -vel * 1.5
						owner_slot = p.slot
						life = 3.0
					elif res == "hit":
						dead = true
					return
		"spore_r", "soul":
			for e in game.enemies.values():
				if hit.has(e.id) or e.hp <= 0:
					continue
				if e.wp.distance_to(wp) < e.radius() + 10.0:
					hit[e.id] = true
					game.damage_enemy(e, 3 if kind == "soul" else 2, wp - vel.normalized() * 30.0, owner_slot, false)
					if kind == "spore_r":
						dead = true
						return

func _draw() -> void:
	match kind:
		"ring", "ring2":
			var a := clampf(1.0 - r / 330.0, 0.0, 1.0)
			var pts := DU.ellipse(Vector2.ZERO, Vector2(r * Iso.A * 1.414, r * Iso.B * 1.414), 48, 0.0, TAU + 0.15)
			draw_polyline(pts, Color(1.0, 0.75, 0.45, 0.35 * a), 16.0)
			draw_polyline(pts, Color(1.0, 0.9, 0.7, 0.95 * a), 3.5)
		"soul":
			var sd: Vector2 = Iso.dir_to_screen(vel)
			var n := Vector2(-sd.y, sd.x)
			var c := Vector2(0, -20)
			DU.glow(self, c, 24.0, Color(0.6, 0.9, 1.0), 0.4)
			DU.flat(self, PackedVector2Array([c - sd * 26.0, c + n * 8.0, c + sd * 14.0, c - n * 8.0]), Color(0.85, 0.97, 1.0))
			DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(10, 4.5), 10), Color(0, 0, 0, 0.3))
		_:
			var col := Color(0.6, 0.95, 0.45) if kind == "spore" else Color(1.0, 0.9, 0.5)
			var c2 := Vector2(0, -18)
			DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(7, 3.2), 10), Color(0, 0, 0, 0.3))
			DU.glow(self, c2, 15.0, col, 0.4)
			DU.ball(self, c2, 6.5 + sin(t * 20.0), col)
