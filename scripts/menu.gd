extends CanvasLayer
# Menus : écran-titre, rejoindre, salon (liste des joueurs), pause.
var game
var screen := "main"
var root: Control
var panels := {}
var status_label: Label
var ip_edit: LineEdit
var lobby_list: Label
var lobby_info: Label
var start_btn: Button
const CFG := "user://ronde.cfg"

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	_build_main()
	_build_join()
	_build_lobby()
	_build_pause()
	show_screen("main" if game.mode == "menu" else "none")

func _theme() -> Theme:
	var th := Theme.new()
	var wood := Color(0.13, 0.095, 0.07)
	var brass := Color(0.85, 0.7, 0.35)
	var pn := StyleBoxFlat.new()
	pn.bg_color = Color(wood, 0.95)
	pn.border_color = brass
	pn.set_border_width_all(2)
	pn.set_corner_radius_all(4)
	pn.set_content_margin_all(18)
	th.set_stylebox("panel", "PanelContainer", pn)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color(0.2, 0.15, 0.1), "hover": Color(0.3, 0.22, 0.13), "pressed": Color(0.38, 0.28, 0.15), "focus": Color(0.3, 0.22, 0.13), "disabled": Color(0.14, 0.12, 0.1)}[st]
		b.border_color = brass if st in ["hover", "focus", "pressed"] else Color(0.4, 0.33, 0.2)
		b.set_border_width_all(2)
		b.set_corner_radius_all(3)
		b.set_content_margin_all(8)
		th.set_stylebox(st, "Button", b)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.06, 0.05, 0.05)
	le.border_color = Color(0.4, 0.33, 0.2)
	le.set_border_width_all(2)
	le.set_content_margin_all(8)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", le)
	th.set_color("font_color", "Label", Color(0.9, 0.88, 0.82))
	return th

func _panel(anchor: int) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(anchor)
	if anchor == Control.PRESET_CENTER:
		pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
		pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
		pc.offset_right = -20
		pc.offset_bottom = -64
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	v.set_meta("panel", pc)
	return v

func _label(v: Container, text: String, size := 15, col := Color(0.9, 0.88, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	v.add_child(l)
	return l

func _button(v: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 44)
	b.pressed.connect(cb)
	v.add_child(b)
	return b

func _build_main() -> void:
	var v := _panel(Control.PRESET_CENTER)
	panels["main"] = v
	_label(v, "La Ronde des Veilleurs", 40, Color(1.0, 0.88, 0.6))
	_label(v, "Roguelite coopératif — 1 à 4 Veilleurs", 15, Color(0.6, 0.7, 0.85))
	v.add_child(Control.new())
	_button(v, "Jouer seul (ou à plusieurs sur cet écran)", func(): game.start_solo())
	_button(v, "Héberger une partie en ligne", func():
		if not game.host_game():
			_refresh())
	_button(v, "Rejoindre une partie en ligne", func(): show_screen("join"))
	_button(v, "Quitter", func(): get_tree().quit())
	status_label = _label(v, "", 14, Color(1.0, 0.7, 0.5))
	_label(v, "Version %s" % ProjectSettings.get_setting("application/config/version", "?"), 12, Color(0.5, 0.56, 0.68))

func _build_join() -> void:
	var v := _panel(Control.PRESET_CENTER)
	panels["join"] = v
	_label(v, "Rejoindre une partie", 26, Color(1.0, 0.88, 0.6))
	_label(v, "Adresse de l'hôte (il la voit dans son salon) :", 14)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "192.168.1.20"
	ip_edit.custom_minimum_size = Vector2(300, 40)
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		ip_edit.text = String(cfg.get_value("net", "last_ip", ""))
	ip_edit.text_submitted.connect(func(_t): _join())
	v.add_child(ip_edit)
	_button(v, "Rejoindre", _join)
	_button(v, "Retour", func(): game.leave())

func _join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("net", "last_ip", ip)
	cfg.save(CFG)
	game.join_game(ip)
	show_screen("main")

func _build_lobby() -> void:
	var v := _panel(Control.PRESET_BOTTOM_RIGHT)
	panels["lobby"] = v
	_label(v, "Salon", 22, Color(1.0, 0.88, 0.6))
	lobby_list = _label(v, "", 15)
	lobby_info = _label(v, "", 12, Color(0.6, 0.7, 0.85))
	start_btn = _button(v, "Lancer la descente (Entrée)", func(): game.host_start_run())
	start_btn.custom_minimum_size = Vector2(260, 40)
	start_btn.focus_mode = Control.FOCUS_NONE
	var q := _button(v, "Quitter le salon", func(): game.leave())
	q.custom_minimum_size = Vector2(260, 36)
	q.focus_mode = Control.FOCUS_NONE

func _build_pause() -> void:
	var v := _panel(Control.PRESET_CENTER)
	panels["pause"] = v
	_label(v, "Pause", 28, Color(1.0, 0.88, 0.6))
	_button(v, "Reprendre", func(): game.toggle_pause())
	_button(v, "Quitter la partie", func(): game.leave())

func show_screen(s: String) -> void:
	screen = s
	for k in panels:
		panels[k].get_meta("panel").visible = k == s
	if panels.has(s) and s != "lobby":
		for c in panels[s].get_children():
			if c is Button:
				c.grab_focus()
				break
	_refresh()

func _process(_d: float) -> void:
	_refresh()

func _refresh() -> void:
	if status_label:
		status_label.text = game.status
	if screen != "lobby" or lobby_list == null:
		return
	var lines := []
	for e in game.roster:
		var who := "vous" if e["peer"] == game.my_id() else ("hôte" if e["peer"] == 1 else "invité")
		lines.append("J%d — %s" % [e["slot"] + 1, who])
	lobby_list.text = "\n".join(lines)
	start_btn.visible = game.is_host()
	var info := ""
	if game.online and game.is_host():
		info = "Adresse à donner (même réseau) :\n%s" % ", ".join(game.local_ips())
		match game.upnp_state:
			"search":
				info += "\nPar internet : recherche de la box…"
			"ok":
				info += "\nPar internet : %s\n(port ouvert automatiquement)" % game.public_ip
			"fail":
				info += "\nPar internet : ouvrir le port UDP %d\nsur la box, ou utiliser Tailscale / ZeroTier" % game.PORT
	elif game.online:
		info = "En attente de l'hôte…"
	else:
		info = "Manette supplémentaire : Start pour rejoindre"
	lobby_info.text = info
