extends Node2D
# Petits effets visuels éphémères.
const Iso = preload("res://scripts/iso.gd")
const DU = preload("res://scripts/draw_util.gd")
var kind := "hit"
var col := Color(1, 1, 1)
var t := 0.0
var life := 0.35
var seed_v := 0.0

func _ready() -> void:
	seed_v = randf() * 100.0
	life = {"hit": 0.22, "death": 0.5, "heal": 0.6, "block": 0.25, "dust": 0.45, "roar": 0.7, "pick": 0.7, "parry": 0.3}.get(kind, 0.35)

func _process(delta: float) -> void:
	t += delta
	if t >= life:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var k := clampf(t / life, 0.0, 1.0)
	var c := Vector2(0, -18)
	match kind:
		"hit":
			for i in 6:
				var a := seed_v + i * TAU / 6.0
				var d := Vector2.from_angle(a)
				draw_line(c + d * (6.0 + k * 10.0), c + d * (14.0 + k * 26.0), Color(1.0, 0.97, 0.85, 1.0 - k), 3.0 * (1.0 - k) + 1.0)
		"death":
			draw_polyline(DU.ellipse(Vector2.ZERO, Vector2(18, 8) * (1.0 + k * 2.2), 24, 0.0, TAU + 0.3), Color(col, 1.0 - k), 3.0)
			for i in 6:
				var a := seed_v + i * 1.3
				DU.flat(self, DU.ellipse(c + Vector2(cos(a) * 22.0 * k, -k * 30.0 + sin(a) * 8.0), Vector2(9, 9) * (1.0 - k * 0.6), 10), Color(0.55, 0.55, 0.65, 0.5 * (1.0 - k)))
		"heal", "pick":
			for i in 5:
				var x := sin(seed_v + i * 2.1) * 16.0
				draw_circle(Vector2(x, -8.0 - k * 46.0 - i * 4.0), 3.0 * (1.0 - k), Color(col, 1.0 - k))
			draw_polyline(DU.ellipse(Vector2.ZERO, Vector2(22, 10) * (1.0 + k), 24, 0.0, TAU + 0.3), Color(col, 0.8 * (1.0 - k)), 2.5)
		"block", "parry":
			draw_arc(c, 14.0 + k * 22.0, 0.0, TAU, 20, Color(0.85, 0.95, 1.0, 1.0 - k), 3.0)
		"dust":
			for i in 7:
				var a := seed_v + i * 0.9
				DU.flat(self, DU.ellipse(Vector2(cos(a) * 46.0 * k, sin(a) * 20.0 * k - k * 12.0), Vector2(11, 8) * (1.0 - k * 0.5), 10), Color(col, 0.4 * (1.0 - k)))
		"roar":
			for i in 3:
				var kk := clampf(k * 1.4 - i * 0.2, 0.0, 1.0)
				draw_polyline(DU.ellipse(Vector2.ZERO, Vector2(60, 27) * (0.4 + kk * 3.0), 32, 0.0, TAU + 0.3), Color(col, 0.8 * (1.0 - kk)), 3.0)
