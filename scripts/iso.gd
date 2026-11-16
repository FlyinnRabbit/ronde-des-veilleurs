# Vue isométrique : la logique vit dans un plan « monde » (x, y au sol, en unités ; 1 case = T),
# l'affichage projette ce plan en losanges.
const T := 48.0          # taille d'une case dans le monde
const A := 0.875         # monde -> écran, axe horizontal (42 px par case)
const B := 0.4375        # monde -> écran, axe vertical (21 px par case)

static func to_screen(w: Vector2) -> Vector2:
	return Vector2((w.x - w.y) * A, (w.x + w.y) * B)

static func to_world(s: Vector2) -> Vector2:
	var u := s.x / A
	var v := s.y / B
	return Vector2((u + v) * 0.5, (v - u) * 0.5)

# Direction à l'écran (stick, souris) -> direction dans le monde.
static func dir_to_world(sd: Vector2) -> Vector2:
	if sd.length_squared() < 0.0001:
		return Vector2.ZERO
	return to_world(sd).normalized()

static func dir_to_screen(wd: Vector2) -> Vector2:
	if wd.length_squared() < 0.0001:
		return Vector2.ZERO
	return to_screen(wd).normalized()
