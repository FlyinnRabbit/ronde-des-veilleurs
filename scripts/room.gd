extends Node2D
# Une salle : grille de cases générée à partir d'une graine (identique chez tous les joueurs),
# collisions, et dessin du sol et des murs du fond.
const Iso = preload("res://scripts/iso.gd")
const DU = preload("res://scripts/draw_util.gd")

const FLOOR := 0
const BLOCK := 1     # pilier : bloque les déplacements et les tirs
const SPIKE := 2     # pics : blessent si on marche dessus (pas pendant la Ruée)
const WALL_H := 74.0

var w := 13
var h := 10
var kind := "combat"     # lobby / combat / rest / boss
var seed_v := 0
var grid := PackedByteArray()
var door_open := false
var pal := {"rock": Color(0.2, 0.25, 0.4), "floor": Color(0.3, 0.36, 0.52), "accent": Color(0.45, 0.75, 0.95)}

func setup(k: String, sd: int, index: int) -> void:
	kind = k
	seed_v = sd
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	match kind:
		"lobby", "rest":
			w = 11
			h = 9
		"boss":
			w = 15
			h = 12
		_:
			w = rng.randi_range(12, 15)
			h = rng.randi_range(9, 11)
	grid.resize(w * h)
	grid.fill(FLOOR)
	if kind == "combat":
		# piliers symétriques
		for i in rng.randi_range(1, 2):
			var px := rng.randi_range(2, w / 2 - 1)
			var py := rng.randi_range(2, h - 4)
			set_cell(px, py, BLOCK)
			set_cell(w - 1 - px, py, BLOCK)
		# plaques de pics
		for i in rng.randi_range(0, 2 + mini(index, 2)):
			var sx := rng.randi_range(1, w - 3)
			var sy := rng.randi_range(1, h - 4)
			for k2 in 2:
				if cell(sx + k2, sy) == FLOOR and absi(sx + k2 - w / 2) > 1:
					set_cell(sx + k2, sy, SPIKE)
	elif kind == "boss":
		for c in [Vector2i(3, 3), Vector2i(w - 4, 3), Vector2i(3, h - 4), Vector2i(w - 4, h - 4)]:
			set_cell(c.x, c.y, BLOCK)
	queue_redraw()

func cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return BLOCK
	return grid[y * w + x]

func set_cell(x: int, y: int, v: int) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		grid[y * w + x] = v

func size_world() -> Vector2:
	return Vector2(w, h) * Iso.T

func center() -> Vector2:
	return size_world() / 2.0

func spawn_point(i: int, n: int) -> Vector2:
	var cx := w * Iso.T / 2.0
	return Vector2(cx + (i - (n - 1) / 2.0) * 46.0, (h - 1.3) * Iso.T)

func door_pos() -> Vector2:
	return Vector2(w * Iso.T / 2.0, 0.0)

func in_door(p: Vector2) -> bool:
	return absf(p.x - door_pos().x) < Iso.T * 1.1 and p.y < Iso.T * 1.2

func blocked_at(p: Vector2) -> bool:
	return cell(int(floor(p.x / Iso.T)), int(floor(p.y / Iso.T))) == BLOCK

func spike_at(p: Vector2) -> bool:
	return cell(int(floor(p.x / Iso.T)), int(floor(p.y / Iso.T))) == SPIKE

# Cercle de rayon r bloqué par un mur ou un pilier ?
func hits(p: Vector2, r: float) -> bool:
	if p.x < r or p.y < r or p.x > w * Iso.T - r or p.y > h * Iso.T - r:
		return true
	var x0 := int(floor((p.x - r) / Iso.T))
	var x1 := int(floor((p.x + r) / Iso.T))
	var y0 := int(floor((p.y - r) / Iso.T))
	var y1 := int(floor((p.y + r) / Iso.T))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if cell(x, y) == BLOCK:
				var nx := clampf(p.x, x * Iso.T, (x + 1) * Iso.T)
				var ny := clampf(p.y, y * Iso.T, (y + 1) * Iso.T)
				if Vector2(nx, ny).distance_squared_to(p) < r * r:
					return true
	return false

# Déplace un cercle en glissant le long des obstacles.
func move(p: Vector2, d: Vector2, r: float, fly := false) -> Vector2:
	if fly:
		var q := p + d
		return Vector2(clampf(q.x, r, w * Iso.T - r), clampf(q.y, r, h * Iso.T - r))
	var steps := int(ceil(d.length() / 12.0))
	if steps < 1:
		steps = 1
	var st := d / steps
	for i in steps:
		if not hits(p + Vector2(st.x, 0), r):
			p.x += st.x
		if not hits(p + Vector2(0, st.y), r):
			p.y += st.y
	return p

func free_spot(rng: RandomNumberGenerator, y_max_frac := 0.6) -> Vector2:
	for i in 40:
		var x := rng.randi_range(1, w - 2)
		var y := rng.randi_range(1, maxi(1, int(h * y_max_frac)))
		if cell(x, y) == FLOOR:
			return Vector2(x + 0.5, y + 0.5) * Iso.T
	return center()

func blocks() -> Array:
	var out := []
	for y in h:
		for x in w:
			if grid[y * w + x] == BLOCK:
				out.append(Vector2i(x, y))
	return out

# ------------------------------------------------------------------ dessin
func S(gx: float, gy: float) -> Vector2:
	return Iso.to_screen(Vector2(gx, gy) * Iso.T)

func _draw() -> void:
	var rock: Color = pal["rock"]
	var fl: Color = pal["floor"]
	var void_c := Color(0.02, 0.025, 0.05)
	for y in h:
		for x in w:
			var hsh := fposmod(sin(x * 12.9898 + y * 78.233 + seed_v * 0.37) * 43758.5453, 1.0)
			var c := fl.darkened(hsh * 0.12)
			if (x + y) % 2 == 0:
				c = c.lightened(0.03)
			var pts := PackedVector2Array([S(x, y), S(x + 1, y), S(x + 1, y + 1), S(x, y + 1)])
			draw_colored_polygon(pts, c)
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.16), 1.0)
			var m := S(x + 0.5, y + 0.5)
			if hsh > 0.82:
				draw_line(m + Vector2(-8, 1), m + Vector2(4, 5), Color(0, 0, 0, 0.22), 1.5)
			elif hsh < 0.14:
				for k in 4:
					draw_line(m + Vector2(k * 4 - 8, 3), m + Vector2(k * 4 - 9 + k, -6), Color(pal["accent"], 0.45), 1.5)
			if grid[y * w + x] == SPIKE:
				draw_colored_polygon(PackedVector2Array([S(x + 0.08, y + 0.08), S(x + 0.92, y + 0.08), S(x + 0.92, y + 0.92), S(x + 0.08, y + 0.92)]), Color(0.05, 0.05, 0.08, 0.55))
				for k in 3:
					for j in 2:
						var b := S(x + 0.22 + k * 0.28, y + 0.3 + j * 0.4)
						draw_colored_polygon(PackedVector2Array([b + Vector2(-5, 0), b + Vector2(0, -15), b + Vector2(5, 0)]), Color(0.78, 0.83, 0.92))
						draw_line(b + Vector2(0, -15), b + Vector2(5, 0), Color(0.4, 0.45, 0.55), 1.0)
	# murs du fond : le long de x = 0 (gauche) et de y = 0 (droite)
	var up := Vector2(0, -WALL_H)
	var a := S(0, h)
	var b0 := S(0, 0)
	var c0 := S(w, 0)
	draw_polygon(PackedVector2Array([a, b0, b0 + up, a + up]), PackedColorArray([rock.darkened(0.3), rock.darkened(0.1), rock.lightened(0.05), rock.darkened(0.15)]))
	draw_polygon(PackedVector2Array([b0, c0, c0 + up, b0 + up]), PackedColorArray([rock.lightened(0.02), rock.darkened(0.2), rock.darkened(0.05), rock.lightened(0.15)]))
	for k in range(1, h):
		draw_line(S(0, k), S(0, k) + up, Color(0, 0, 0, 0.2), 1.5)
	for k in range(1, w):
		draw_line(S(k, 0), S(k, 0) + up, Color(0, 0, 0, 0.2), 1.5)
	draw_line(a + up * 0.5, b0 + up * 0.5, Color(0, 0, 0, 0.18), 1.5)
	draw_line(b0 + up * 0.5, c0 + up * 0.5, Color(0, 0, 0, 0.18), 1.5)
	var th := 0.9
	draw_colored_polygon(PackedVector2Array([a + up, b0 + up, S(-th, -th) + up, S(-th, h) + up]), rock.darkened(0.45))
	draw_colored_polygon(PackedVector2Array([b0 + up, c0 + up, S(w, -th) + up, S(-th, -th) + up]), rock.darkened(0.4))
	draw_polyline(PackedVector2Array([a + up, b0 + up, c0 + up]), rock.lightened(0.4), 2.0)
	# stalactites
	for k in range(1, w, 2):
		var sp := S(k + 0.5, 0) + up
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-7, 3), sp + Vector2(7, -3), sp + Vector2(0, 20 + (k % 3) * 7)]), rock.darkened(0.35))
	# bord avant de la plateforme
	var d0 := S(w, h)
	var dn := Vector2(0, 30)
	draw_polygon(PackedVector2Array([a, d0, d0 + dn, a + dn]), PackedColorArray([rock.darkened(0.35), rock.darkened(0.35), void_c, void_c]))
	draw_polygon(PackedVector2Array([d0, c0, c0 + dn, d0 + dn]), PackedColorArray([rock.darkened(0.5), rock.darkened(0.5), void_c, void_c]))
	_draw_door()

func _draw_door() -> void:
	if kind == "lobby":
		return
	# portail sur le mur du fond (y = 0), suit l'inclinaison du mur
	var c := S(w / 2.0, 0)
	var ax := (S(w / 2.0 + 1.0, 0) - c)      # une case le long du mur
	var up := Vector2(0, -1)
	var hw := 0.62
	var frame := PackedVector2Array([c - ax * hw, c - ax * hw + up * 50, c - ax * hw * 0.55 + up * 64, c + ax * hw * 0.55 + up * 64, c + ax * hw + up * 50, c + ax * hw])
	draw_colored_polygon(frame, Color(0.3, 0.26, 0.22))
	var iw := hw - 0.12
	var inner := PackedVector2Array([c - ax * iw, c - ax * iw + up * 47, c - ax * iw * 0.5 + up * 58, c + ax * iw * 0.5 + up * 58, c + ax * iw + up * 47, c + ax * iw])
	if door_open:
		draw_colored_polygon(inner, Color(0.6, 0.85, 1.0))
		DU.glow(self, c + up * 26, 54.0, Color(0.6, 0.85, 1.0), 0.3)
	else:
		draw_colored_polygon(inner, Color(0.07, 0.07, 0.1))
		for k in 4:   # herse
			var t := (k + 0.5) / 4.0
			var p0 := (c - ax * iw).lerp(c + ax * iw, t)
			draw_line(p0, p0 + up * 50, Color(0.45, 0.45, 0.5), 2.5)
	frame.append(frame[0])
	draw_polyline(frame, Color(0.1, 0.08, 0.07), 2.0)
