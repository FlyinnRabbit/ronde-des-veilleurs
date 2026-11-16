# Lecture des commandes par périphérique (plusieurs joueurs sur la même machine).
# device : "any" (clavier/souris + manette 0), "kb" (clavier/souris), 0..7 (manette), "bot", "none".
# Les directions renvoyées sont des directions À L'ÉCRAN.

static func pad_ok(d: int) -> bool:
	return d in Input.get_connected_joypads()

static func _stick(d: int, ax: int, ay: int) -> Vector2:
	var v := Vector2(Input.get_joy_axis(d, ax), Input.get_joy_axis(d, ay))
	return v if v.length() > 0.25 else Vector2.ZERO

static func _kb() -> Dictionary:
	var m := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		m.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		m.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		m.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		m.y += 1
	return {
		"move": m.normalized(), "aim": Vector2.ZERO, "mouse": true,
		"attack": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_J),
		"dash": Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SHIFT),
		"parry": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(KEY_K),
		"spell": Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_O),
		"heal": Input.is_physical_key_pressed(KEY_F) or Input.is_physical_key_pressed(KEY_L),
		"start": Input.is_physical_key_pressed(KEY_ENTER),
	}

static func _pad(d: int) -> Dictionary:
	var m := _stick(d, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT):
		m.x -= 1
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT):
		m.x += 1
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP):
		m.y -= 1
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN):
		m.y += 1
	return {
		"move": m.limit_length(1.0), "aim": _stick(d, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).normalized(), "mouse": false,
		"attack": Input.is_joy_button_pressed(d, JOY_BUTTON_X),
		"dash": Input.is_joy_button_pressed(d, JOY_BUTTON_A) or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5,
		"parry": Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.5,
		"spell": Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_Y),
		"heal": Input.is_joy_button_pressed(d, JOY_BUTTON_B),
		"start": Input.is_joy_button_pressed(d, JOY_BUTTON_START),
	}

static func empty() -> Dictionary:
	return {"move": Vector2.ZERO, "aim": Vector2.ZERO, "mouse": false, "attack": false, "dash": false, "parry": false, "spell": false, "heal": false, "start": false}

static func read(device) -> Dictionary:
	if device is int:
		return _pad(device) if pad_ok(device) else empty()
	match String(device):
		"kb":
			return _kb()
		"any":
			var k := _kb()
			if pad_ok(0):
				var p := _pad(0)
				var pad_active: bool = p["move"] != Vector2.ZERO or p["aim"] != Vector2.ZERO
				for key in ["attack", "dash", "parry", "spell", "heal", "start"]:
					if p[key]:
						pad_active = true
					k[key] = k[key] or p[key]
				if k["move"] == Vector2.ZERO:
					k["move"] = p["move"]
				if pad_active:
					k["aim"] = p["aim"]
					k["mouse"] = false
			return k
	return empty()
