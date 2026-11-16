extends Node2D
# Décor posé dans la salle (trié en profondeur avec les personnages).
const Iso = preload("res://scripts/iso.gd")
const DU = preload("res://scripts/draw_util.gd")

var game
var kind := "pillar"
var wp := Vector2.ZERO
var col := Color(0.2, 0.25, 0.4)
var boon := ""          # socle d'emblème
var progress := {}      # socle : avancement par joueur (0..1)
var t := 0.0

func _ready() -> void:
	position = Iso.to_screen(wp)
	if kind in ["lantern", "crystal", "pedestal"]:
		var l := PointLight2D.new()
		l.texture = DU.radial_texture(256)
		l.texture_scale = 4.2 if kind == "lantern" else 1.6
		l.energy = 0.8 if kind == "lantern" else (0.25 if kind == "pedestal" else 0.5)
		l.color = Color(1.0, 0.82, 0.5) if kind == "lantern" else (Color(0.5, 0.8, 1.0) if kind == "crystal" else Color(1.0, 0.9, 0.6))
		l.position = Vector2(0, -40)
		add_child(l)

func _process(delta: float) -> void:
	t += delta
	if kind in ["pedestal", "lantern"]:
		queue_redraw()

func _draw() -> void:
	match kind:
		"pillar":
			var h := Iso.T / 2.0
			var up := Vector2(0, -54)
			var n := Iso.to_screen(Vector2(-h, -h))
			var e := Iso.to_screen(Vector2(h, -h))
			var s := Iso.to_screen(Vector2(h, h))
			var w := Iso.to_screen(Vector2(-h, h))
			draw_polygon(PackedVector2Array([w, s, s + up, w + up]), PackedColorArray([col.darkened(0.35), col.darkened(0.35), col.darkened(0.1), col.darkened(0.1)]))
			draw_polygon(PackedVector2Array([s, e, e + up, s + up]), PackedColorArray([col.darkened(0.5), col.darkened(0.5), col.darkened(0.3), col.darkened(0.3)]))
			draw_colored_polygon(PackedVector2Array([n + up, e + up, s + up, w + up]), col.lightened(0.12))
			draw_polyline(PackedVector2Array([w + up, s + up, e + up]), col.lightened(0.4), 2.0)
			draw_line(s, s + up, Color(0, 0, 0, 0.25), 1.5)
			draw_line((w + s) / 2.0 + up * 0.5, (s + e) / 2.0 + up * 0.5, Color(0, 0, 0, 0.0), 1.0)
		"lantern":
			DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(14, 6), 14), Color(0, 0, 0, 0.4))
			draw_line(Vector2.ZERO, Vector2(0, -52), Color(0.25, 0.2, 0.16), 5.0)
			DU.glow(self, Vector2(0, -62), 56.0 + sin(t * 3.0) * 3.0, Color(1.0, 0.8, 0.4), 0.3)
			DU.box(self, Rect2(Vector2(-9, -74), Vector2(18, 22)), Color(0.3, 0.24, 0.16))
			draw_rect(Rect2(Vector2(-6, -71), Vector2(12, 16)), Color(1.0, 0.9, 0.55))
			DU.flat(self, PackedVector2Array([Vector2(-11, -74), Vector2(0, -84), Vector2(11, -74)]), Color(0.25, 0.2, 0.14))
		"bench":
			DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(26, 10), 14), Color(0, 0, 0, 0.4))
			DU.box(self, Rect2(Vector2(-24, -14), Vector2(48, 6)), Color(0.45, 0.3, 0.18))
			DU.box(self, Rect2(Vector2(-24, -28), Vector2(48, 5)), Color(0.45, 0.3, 0.18))
			draw_line(Vector2(-20, -28), Vector2(-20, 0), Color(0.25, 0.22, 0.24), 3.0)
			draw_line(Vector2(20, -28), Vector2(20, 0), Color(0.25, 0.22, 0.24), 3.0)
		"crystal":
			DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(16, 7), 14), Color(0, 0, 0, 0.4))
			DU.glow(self, Vector2(0, -14), 32.0, Color(0.5, 0.8, 1.0), 0.22)
			for k in 3:
				var b := Vector2(-9 + k * 9, 0)
				var hh := 20.0 + (k % 2) * 14.0
				DU.poly(self, PackedVector2Array([b + Vector2(-5, 0), b + Vector2(-3, -hh), b + Vector2(1, -hh - 6), b + Vector2(5, -hh + 3), b + Vector2(5, 0)]), Color(0.45, 0.75, 0.95))
		"pedestal":
			_pedestal()

func _pedestal() -> void:
	var info: Dictionary = game.BOONS.get(boon, {})
	var c: Color = info.get("col", Color(1, 1, 1))
	DU.flat(self, DU.ellipse(Vector2.ZERO, Vector2(20, 9), 14), Color(0, 0, 0, 0.4))
	DU.poly(self, PackedVector2Array([Vector2(-14, 0), Vector2(-10, -18), Vector2(10, -18), Vector2(14, 0)]), Color(0.36, 0.34, 0.42))
	var m := Vector2(0, -40 + sin(t * 2.5) * 3.0)
	DU.glow(self, m, 26.0, c, 0.35)
	DU.ball(self, m, 13.0, Color(0.2, 0.16, 0.12))
	draw_arc(m, 13.0, 0.0, TAU, 24, Color(0.85, 0.7, 0.35), 2.5)
	DU.flat(self, DU.diamond(m, Vector2(6, 8)), c)
	var near := false
	var best := 0.0
	for p in game.players.values():
		if p.local and p.wp.distance_to(wp) < 90.0:
			near = true
		best = maxf(best, float(progress.get(p.slot, 0.0)))
	if best > 0.0:
		draw_arc(Vector2(0, -40), 22.0, -PI / 2.0, -PI / 2.0 + TAU * best, 24, Color(1, 1, 1, 0.9), 3.0)
	if near:
		var f := ThemeDB.fallback_font
		var nm := String(info.get("name", boon))
		var ds := String(info.get("desc", ""))
		var w := maxf(f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, f.get_string_size(ds, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 20.0
		draw_rect(Rect2(-w / 2.0, -106, w, 42), Color(0.08, 0.06, 0.05, 0.92))
		draw_rect(Rect2(-w / 2.0, -106, w, 42), Color(0.85, 0.7, 0.35), false, 1.5)
		draw_string(f, Vector2(-w / 2.0, -88), nm, HORIZONTAL_ALIGNMENT_CENTER, w, 15, c)
		draw_string(f, Vector2(-w / 2.0, -72), ds, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.85, 0.85, 0.9))
