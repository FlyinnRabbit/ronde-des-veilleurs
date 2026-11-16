# Petites fonctions de dessin partagées (tout le jeu est dessiné en code, sans images).

static func ellipse(c: Vector2, r: Vector2, n: int = 24, a0: float = 0.0, a1: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var full := (a1 - a0) >= TAU - 0.001
	for i in (n if full else n + 1):
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

static func diamond(c: Vector2, r: Vector2) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r.y), c + Vector2(r.x, 0), c + Vector2(0, r.y), c + Vector2(-r.x, 0)])

static func radial_texture(size: int = 256) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t

# ---------------------------------------------------------------- rendu « peint »
# Polygone ombré : dégradé éclairé en haut à gauche, contour sombre et liseré de lumière
# sur les bords tournés vers le haut. Les formes translucides (lueurs) restent plates.
static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, outline := true) -> void:
	if pts.size() < 3:
		return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return   # forme dégénérée (croisée) : rien à dessiner
	if col.a < 0.95:
		ci.draw_colored_polygon(pts, col)
		return
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var sz := (mx - mn).max(Vector2(1, 1))
	var hi := lit(col, 1.38, 0.03)
	var lo := col.darkened(0.5)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		var t := clampf(((pts[i].y - mn.y) / sz.y) * 0.75 + ((pts[i].x - mn.x) / sz.x) * 0.25, 0.0, 1.0)
		cols[i] = hi.lerp(lo, t)
	ci.draw_polygon(pts, cols)
	if not outline or sz.x < 5.0 or sz.y < 5.0:
		return
	# sens du tracé pour orienter les normales vers l'extérieur
	var area := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var rim := lit(col, 1.9, 0.08)
	rim.a = 0.85
	var edge := col.darkened(0.7)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		var n := Vector2(d.y, -d.x).normalized() * sgn
		if n.y < -0.45:
			ci.draw_line(a - n * 0.9, b - n * 0.9, rim, 1.3)
		elif n.y > 0.3:
			ci.draw_line(a, b, edge, 1.6)

# Éclaircit en gardant la teinte (multiplicatif + un peu d'additif)
static func lit(c: Color, m: float, a: float) -> Color:
	return Color(minf(c.r * m + a, 1.0), minf(c.g * m + a, 1.0), minf(c.b * m + a, 1.0), c.a)

# Disque ombré (sphère peinte) ; petits points et lueurs restent plats.
static func ball(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r < 3.5 or col.a < 0.95:
		ci.draw_circle(c, r, col)
		return
	ci.draw_circle(c, r, col.darkened(0.45))
	ci.draw_circle(c + Vector2(-0.16, -0.2) * r, r * 0.74, col)
	var h := lit(col, 1.5, 0.06)
	h.a = 0.75
	ci.draw_circle(c + Vector2(-0.34, -0.4) * r, r * 0.3, h)

# Rectangle à dégradé vertical (haut, bas)
static func vgrad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

# Halo doux : disques concentriques très transparents (pas de bord net)
static func glow(ci: CanvasItem, c: Vector2, r: float, col: Color, a := 0.25) -> void:
	var n := clampi(int(r / 5.0), 10, 40)
	for i in n:
		var k := 1.0 - float(i) / n
		ci.draw_circle(c, r * k, Color(col, a / n))

# Rectangle peint : dégradé, arête haute éclairée, base sombre (les rectangles translucides restent plats)
static func box(ci: CanvasItem, r: Rect2, col: Color) -> void:
	if col.a < 0.95 or r.size.x < 3.0 or r.size.y < 3.0:
		ci.draw_rect(r, col)
		return
	vgrad(ci, r, lit(col, 1.25, 0.03), col.darkened(0.4))
	ci.draw_line(r.position + Vector2(0, 0.6), Vector2(r.end.x, r.position.y + 0.6), lit(col, 1.7, 0.08), 1.2)
	ci.draw_line(Vector2(r.position.x, r.end.y - 0.6), r.end - Vector2(0, 0.6), col.darkened(0.65), 1.2)
	ci.draw_line(r.position, Vector2(r.position.x, r.end.y), col.darkened(0.5), 1.0)

# Polygone plat, ignoré s'il est dégénéré (croisé) au lieu de produire une erreur
static func flat(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
		return
	ci.draw_colored_polygon(pts, col)
