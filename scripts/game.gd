extends Node2D
# La Ronde des Veilleurs — chef d'orchestre : réseau (hôte / invités), salles, règles du jeu.
#
# Réseau : un joueur héberge (il fait tourner les ennemis, les dégâts et la progression),
# les autres rejoignent. Chaque joueur décide de la position de son propre Veilleur et
# l'envoie 30 fois par seconde ; l'hôte envoie l'état du monde 20 fois par seconde.
# En solo, on est simplement l'hôte d'une partie sans invités.
const Iso = preload("res://scripts/iso.gd")
const DU = preload("res://scripts/draw_util.gd")
const Inputs = preload("res://scripts/inputs.gd")
const RoomScript = preload("res://scripts/room.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const ShotScript = preload("res://scripts/shot.gd")
const PropScript = preload("res://scripts/prop.gd")
const FxScript = preload("res://scripts/fx.gd")
const HudScript = preload("res://scripts/hud.gd")
const MenuScript = preload("res://scripts/menu.gd")

const PORT := 24565
const MAX_PLAYERS := 4
const RUN := ["combat", "combat", "combat", "rest", "combat", "combat", "boss"]
const BOONS := {
	"aiguille": {"name": "Aiguille Longue", "desc": "Portée des coups +35 %", "col": Color(0.75, 0.85, 1.0)},
	"coeur": {"name": "Cœur de Verre", "desc": "+2 masques de vie", "col": Color(0.95, 0.6, 0.7)},
	"cape": {"name": "Cape Rapide", "desc": "Course +12 %, Ruée plus fréquente", "col": Color(0.5, 0.9, 0.85)},
	"coquille": {"name": "Coquille Épineuse", "desc": "Blesse les ennemis proches quand on est touché", "col": Color(0.55, 0.75, 0.45)},
	"miroir": {"name": "Miroir Parfait", "desc": "Parade presque deux fois plus longue", "col": Color(0.9, 0.95, 1.0)},
	"ame": {"name": "Âme Vorace", "desc": "+60 % d'âme à chaque coup", "col": Color(0.8, 0.7, 1.0)},
	"concentration": {"name": "Concentration Vive", "desc": "Soin deux fois plus rapide", "col": Color(1.0, 0.95, 0.7)},
	"force": {"name": "Force Brute", "desc": "+1 dégât, coups un peu plus lents", "col": Color(1.0, 0.55, 0.4)},
}

var world: Node2D
var room: Node2D
var ents: Node2D
var hud
var menu
var players := {}        # emplacement (0..3) -> Veilleur
var enemies := {}        # id -> ennemi
var shots := {}          # id -> tir
var pedestals: Array = []
var roster: Array = []   # [{slot, peer, lidx, boons}]
var local_devices := {}  # indice local -> périphérique
var mode := "menu"       # menu / lobby / run
var online := false
var room_index := -1
var room_kind := "lobby"
var phase := "idle"      # fight / clear / over
var door_open := false
var shards := 0
var clock := 0.0
var next_id := 1
var shake_amt := 0.0
var waves_left := 0
var door_t := 0.0
var hold_t := 0.0
var over_t := 0.0
var snap_t := 0.0
var run_seed := 0
var banner := ""
var banner_t := 0.0
var status := ""          # message réseau affiché dans le menu
var door_count := Vector2i.ZERO
var prev_start := {}
# tests en ligne de commande
var opt_bot := false
var opt_autostart := 0
var opt_quit := false
var opt_debug := false
var opt_room := 0          # tests : salle de départ
var opt_god := false       # tests : les Veilleurs ne prennent pas de dégâts
var opt_shots := ""     # tests : préfixe de captures d'écran périodiques
var _shot_t := 2.0
var _shot_n := 0
var _dbg_t := 0.0
var solo_pause := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cm := CanvasModulate.new()
	cm.color = Color(0.5, 0.54, 0.7)
	add_child(cm)
	world = Node2D.new()
	add_child(world)
	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	hud.game = self
	add_child(hud)
	menu = CanvasLayer.new()
	menu.set_script(MenuScript)
	menu.game = self
	add_child(menu)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _back_to_menu("Connexion impossible."))
	multiplayer.server_disconnected.connect(func(): _back_to_menu("L'hôte a quitté la partie."))
	_parse_args()

func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	opt_bot = "--bot" in a
	opt_quit = "--quit-after-run" in a
	opt_debug = "--debug-log" in a
	opt_god = "--god" in a
	var ri := a.find("--room")
	if ri >= 0 and ri + 1 < a.size():
		opt_room = int(a[ri + 1])
	var si := a.find("--shots")
	if si >= 0 and si + 1 < a.size():
		opt_shots = a[si + 1]
	var i := a.find("--autostart")
	if i >= 0:
		opt_autostart = int(a[i + 1]) if i + 1 < a.size() and a[i + 1].is_valid_int() else 1
	if "--solo" in a:
		start_solo()
	elif "--host" in a:
		host_game()
	else:
		var j := a.find("--join")
		if j >= 0 and j + 1 < a.size():
			join_game(a[j + 1])

func is_host() -> bool:
	return multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id()

func frozen() -> bool:
	return hold_t > 0.0 or solo_pause or mode == "menu"

func log_line(s: String) -> void:
	print("[ronde] ", s)

# ================================================================== sessions
func start_solo() -> void:
	_close_peer()
	online = false
	_begin_session()

func host_game() -> bool:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		status = "Impossible d'ouvrir le port %d (déjà utilisé ?)." % PORT
		return false
	multiplayer.multiplayer_peer = peer
	online = true
	start_upnp()
	_begin_session()
	return true

func join_game(ip: String) -> bool:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip.strip_edges(), PORT) != OK:
		status = "Adresse invalide."
		return false
	multiplayer.multiplayer_peer = peer
	online = true
	status = "Connexion à %s…" % ip
	mode = "menu"
	return true

func _begin_session() -> void:
	roster = []
	local_devices = {0: "bot" if opt_bot else "any"}
	status = ""
	_host_add(1, 0)
	_host_start_room(-1)

func _on_connected() -> void:
	local_devices = {0: "bot" if opt_bot else "any"}
	status = ""
	rpc_id(1, "req_add", 0)

func _close_peer() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func leave() -> void:
	_back_to_menu("")

func _back_to_menu(msg: String) -> void:
	_close_peer()
	online = false
	mode = "menu"
	status = msg
	solo_pause = false
	if opt_quit:
		get_tree().quit()
	_clear_world(true)
	roster = []
	Audio.music("sanctuaire")
	menu.show_screen("main")

# ------------------------------------------------------------------ liste des joueurs
func _host_add(peer: int, lidx: int) -> void:
	for e in roster:
		if e["peer"] == peer and e["lidx"] == lidx:
			return
	var used := {}
	for e in roster:
		used[e["slot"]] = true
	for s in MAX_PLAYERS:
		if not used.has(s):
			roster.append({"slot": s, "peer": peer, "lidx": lidx, "boons": []})
			roster.sort_custom(func(a, b): return a["slot"] < b["slot"])
			rpc("sync_roster", roster)
			log_line("joueur %d ajouté (pair %d)" % [s + 1, peer])
			return

@rpc("any_peer", "call_remote", "reliable")
func req_add(lidx: int) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	_host_add(peer, clampi(lidx, 0, 3))
	# le nouveau venu reçoit la salle en cours
	rpc_id(peer, "r_room", room_index, room_kind, _room_seed(room_index), mode)

func _on_peer_left(id: int) -> void:
	if not is_host():
		return
	roster = roster.filter(func(e): return e["peer"] != id)
	rpc("sync_roster", roster)
	log_line("le pair %d est parti" % id)

@rpc("authority", "call_local", "reliable")
func sync_roster(r: Array) -> void:
	roster = r
	var keep := {}
	for e in roster:
		var s: int = e["slot"]
		keep[s] = true
		if not players.has(s):
			var p := Node2D.new()
			p.set_script(PlayerScript)
			p.game = self
			p.slot = s
			p.peer = e["peer"]
			p.lidx = e["lidx"]
			p.local = e["peer"] == my_id()
			p.device = local_devices.get(e["lidx"], "none") if p.local else "remote"
			if room:
				p.wp = room.spawn_point(s, MAX_PLAYERS)
			players[s] = p
			if ents:
				ents.add_child(p)
		players[s].boons = e["boons"]
	for s in players.keys():
		if not keep.has(s):
			players[s].queue_free()
			players.erase(s)

func roster_entry(slot: int) -> Variant:
	for e in roster:
		if e["slot"] == slot:
			return e
	return null

func _owns(sender: int, slot: int) -> bool:
	var e = roster_entry(slot)
	if e == null:
		return false
	return e["peer"] == (sender if sender != 0 else my_id())

# Joueurs supplémentaires sur la même machine : appuyer sur Start d'une manette libre (au salon).
func _poll_local_joins() -> void:
	if mode != "lobby" or opt_bot:
		return
	for d in Input.get_connected_joypads():
		var now := Input.is_joy_button_pressed(d, JOY_BUTTON_START)
		var was: bool = prev_start.get(d, false)
		prev_start[d] = now
		if not now or was or d in local_devices.values():
			continue
		if d == 0 and local_devices.get(0, "") == "any":
			# la manette 0 devient un joueur à part : le premier garde le clavier et la souris
			local_devices[0] = "kb"
			if players.has(_slot_of_local(0)):
				players[_slot_of_local(0)].device = "kb"
		var lidx := 1
		while local_devices.has(lidx):
			lidx += 1
		if lidx > 3 or roster.size() >= MAX_PLAYERS:
			return
		local_devices[lidx] = d
		if is_host():
			_host_add(1, lidx)
		else:
			rpc_id(1, "req_add", lidx)

func _slot_of_local(lidx: int) -> int:
	for e in roster:
		if e["peer"] == my_id() and e["lidx"] == lidx:
			return e["slot"]
	return -1

# ================================================================== salles
func _room_seed(index: int) -> int:
	return run_seed + (index + 2) * 7919

func _clear_world(with_players: bool) -> void:
	for e in enemies.values():
		e.queue_free()
	for s in shots.values():
		s.queue_free()
	enemies.clear()
	shots.clear()
	pedestals.clear()
	if with_players:
		players.clear()
		for c in world.get_children():
			c.queue_free()
		room = null
		ents = null
	elif ents:
		for c in ents.get_children():
			if not (c in players.values()):
				c.queue_free()

func _host_start_room(index: int) -> void:
	var kind: String = "lobby" if index < 0 else RUN[index]
	if index < 0:
		mode = "lobby"
	else:
		mode = "run"
	rpc("r_room", index, kind, _room_seed(index), mode)
	phase = "idle"
	door_t = 0.0
	for p in players.values():
		p.picked = false
		if p.down or index <= 0:
			p.down = false
			p.hp = maxi(p.hp, 2) if index > 0 else p.max_hp
	var n := maxi(1, players.size())
	match kind:
		"combat":
			phase = "fight"
			waves_left = 1 if index >= 2 else 0
			_spawn_wave(index, n)
		"boss":
			phase = "fight"
			waves_left = 0
			spawn_enemy("gardien", Vector2(room.w * Iso.T / 2.0, Iso.T * 3.0))
		"rest":
			for p in players.values():
				p.hp = p.max_hp
				p.down = false
			door_open = true
			room.door_open = true
			room.queue_redraw()
	log_line("salle %d (%s)" % [index + 1, kind])

func _spawn_wave(index: int, n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _room_seed(index) + waves_left * 31
	var pool := ["rampant", "rampant", "volant"]
	if index >= 1:
		pool.append("cracheur")
	if index >= 2:
		pool.append("garde")
	if index >= 4:
		pool.append_array(["garde", "cracheur", "volant"])
	var count := 2 + mini(index, 4) + (n - 1) * 2
	for i in count:
		spawn_enemy(pool[rng.randi() % pool.size()], room.free_spot(rng))

@rpc("authority", "call_local", "reliable")
func r_room(index: int, kind: String, sd: int, md: String) -> void:
	mode = md
	room_index = index
	room_kind = kind
	door_open = false
	banner_t = 0.0
	hold_t = 0.5
	_clear_world(false)
	if room == null:
		room = Node2D.new()
		room.set_script(RoomScript)
		room.z_index = -10
		world.add_child(room)
		ents = Node2D.new()
		ents.y_sort_enabled = true
		world.add_child(ents)
		for p in players.values():
			if p.get_parent() == null:
				ents.add_child(p)
	room.door_open = false
	room.setup(kind, sd, index)
	for b in room.blocks():
		_prop("pillar", (Vector2(b) + Vector2(0.5, 0.5)) * Iso.T)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd + 5
	for i in 2:
		_prop("crystal", Vector2((0.6 if i == 0 else room.w - 0.6), rng.randf_range(1.5, room.h - 1.5)) * Iso.T)
	if kind in ["lobby", "rest"]:
		_prop("lantern", room.center())
		_prop("bench", room.center() + Vector2(-2.2, -1.6) * Iso.T)
	var i2 := 0
	for s in players.keys():
		players[s].place(room.spawn_point(i2, players.size()))
		i2 += 1
	world.position = get_viewport_rect().size / 2.0 - Iso.to_screen(room.center()) + Vector2(0, 46)
	Audio.music("boss_gardien_du_puits" if kind == "boss" else ("sanctuaire" if kind in ["lobby", "rest"] else "profondeurs_puits_d_ombre"))
	if mode != "menu":
		menu.show_screen("lobby" if mode == "lobby" else "none")

func _prop(kind: String, wp: Vector2, boon := "") -> Node2D:
	var p := Node2D.new()
	p.set_script(PropScript)
	p.game = self
	p.kind = kind
	p.wp = wp
	p.boon = boon
	p.col = room.pal["rock"]
	ents.add_child(p)
	return p

func host_start_run() -> void:
	if not is_host() or mode != "lobby":
		return
	run_seed = randi() % 1000000
	shards = 0
	for e in roster:
		e["boons"] = []
	rpc("sync_roster", roster)
	for p in players.values():
		p.max_hp = 5
		p.hp = 5
		p.soul = 0
		p.down = false
	_host_start_room(opt_room)

# ================================================================== boucle
func _process(delta: float) -> void:
	clock += delta
	shake_amt = move_toward(shake_amt, 0.0, delta * 30.0)
	banner_t = maxf(0.0, banner_t - delta)
	hold_t = maxf(0.0, hold_t - delta)
	if room:
		world.position = get_viewport_rect().size / 2.0 - Iso.to_screen(room.center()) + Vector2(0, 46) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
	if opt_shots != "":
		_shot_t -= delta
		if _shot_t <= 0.0:
			_shot_t = 2.5
			get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [opt_shots, _shot_n])
			_shot_n += 1
	if mode == "menu":
		return
	_poll_local_joins()
	for id in shots.keys():
		if shots[id].dead and is_host():
			shots[id].queue_free()
			shots.erase(id)
	if is_host() and not solo_pause:
		_host_tick(delta)
	elif opt_debug and not is_host():
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = 4.0
			var ps := []
			for p in players.values():
				ps.append("J%d(%d,%d pv%d âme%d%s%s)" % [p.slot + 1, p.wp.x, p.wp.y, p.hp, p.soul, " local" if p.local else "", " à terre" if p.down else ""])
			log_line("invité t=%.0f salle=%d %s porte=%s ennemis=%d tirs=%d socles=%d | %s" % [clock, room_index + 1, room_kind, door_open, enemies.size(), shots.size(), pedestals.size(), " ".join(ps)])

func _host_tick(delta: float) -> void:
	var alive := 0
	for p in players.values():
		if not p.down:
			alive += 1
			if room.spike_at(p.wp) and (p.flags & 1) == 0 and p.spike_t <= 0.0:
				p.spike_t = 0.8
				hurt_player(p, 1, p.wp - p.aim * 10.0, false)
	if mode == "run":
		if phase == "fight" and enemies.is_empty() and hold_t <= 0.0:
			if waves_left > 0:
				waves_left -= 1
				_spawn_wave(room_index, maxi(1, players.size()))
			else:
				_room_cleared()
		if phase == "clear":
			_tick_pedestals(delta)
		_tick_revive(delta)
		if phase != "over" and players.size() > 0 and alive == 0:
			phase = "over"
			over_t = 4.0
			ev_all("banner", ["La ronde s'achève ici…", 4.0])
			log_line("défaite salle %d" % (room_index + 1))
		if phase == "over":
			over_t -= delta
			if over_t <= 0.0:
				if opt_quit:
					get_tree().quit()
				_host_start_room(-1)
				return
		# portail : tous les Veilleurs debout doivent s'y tenir
		if door_open and phase != "over":
			var inside := 0
			for p in players.values():
				if not p.down and room.in_door(p.wp):
					inside += 1
			door_count = Vector2i(inside, alive)
			if alive > 0 and inside == alive:
				door_t += delta
				if door_t >= 0.6:
					_host_start_room(room_index + 1)
					return
			else:
				door_t = 0.0
	elif mode == "lobby" and opt_autostart > 0 and players.size() >= opt_autostart and clock > 1.5:
		opt_autostart = 0
		host_start_run()
	if opt_debug:
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = 4.0
			var es := []
			for e in enemies.values():
				es.append("%s(%d,%d pv%d %s)" % [e.kind, e.wp.x, e.wp.y, e.hp, e.state])
			var ps := []
			for p in players.values():
				ps.append("J%d(%d,%d pv%d âme%d%s)" % [p.slot + 1, p.wp.x, p.wp.y, p.hp, p.soul, " à terre" if p.down else ""])
			log_line("t=%.0f %s phase=%s porte=%s | %s | %s" % [clock, room_kind, phase, door_open, " ".join(ps), " ".join(es)])
	snap_t -= delta
	if snap_t <= 0.0:
		snap_t = 0.05
		if online:
			rpc("r_snap", _snapshot())

func _room_cleared() -> void:
	phase = "clear"
	if room_kind == "boss":
		phase = "over"
		over_t = 6.0
		ev_all("banner", ["Le Gardien est tombé — la Lanterne brille !", 6.0])
		log_line("victoire, %d éclats" % shards)
		return
	door_open = true
	room.door_open = true
	room.queue_redraw()
	ev_all("door", [])
	# trois emblèmes au choix (un par Veilleur)
	var rng := RandomNumberGenerator.new()
	rng.seed = _room_seed(room_index) + 99
	var ids: Array = BOONS.keys()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	_set_pedestals(ids.slice(0, 3))
	log_line("salle %d nettoyée" % (room_index + 1))

func _set_pedestals(ids: Array) -> void:
	for p in pedestals:
		p.queue_free()
	pedestals.clear()
	var c: Vector2 = Vector2(room.w * Iso.T / 2.0, room.h * Iso.T * 0.45)
	for i in ids.size():
		var pos := c + Vector2((i - (ids.size() - 1) / 2.0) * 110.0, 0)
		var tries := 0
		while (room.hits(pos, 30.0) or room.spike_at(pos)) and tries < 6:   # pas dans un pilier ni sur des pics
			pos.y += Iso.T
			tries += 1
		pedestals.append(_prop("pedestal", pos, String(ids[i])))

func _tick_pedestals(delta: float) -> void:
	for ped in pedestals:
		for p in players.values():
			var v: float = ped.progress.get(p.slot, 0.0)
			if not p.picked and not p.down and p.wp.distance_to(ped.wp) < 38.0:
				v += delta / 0.8
				if v >= 1.0:
					v = 0.0
					_give_boon(p, ped.boon)
			else:
				v = 0.0
			ped.progress[p.slot] = v

func _give_boon(p, boon: String) -> void:
	p.picked = true
	var e = roster_entry(p.slot)
	if e == null:
		return
	if boon in e["boons"]:
		p.hp = mini(p.max_hp, p.hp + 2)      # déjà possédé : soigne à la place
	else:
		e["boons"].append(boon)
		if boon == "coeur":
			p.max_hp += 2
			p.hp += 2
		rpc("sync_roster", roster)
	ev_all("pick", [p.slot, boon])

func _tick_revive(delta: float) -> void:
	for p in players.values():
		if not p.down:
			continue
		var helped := false
		for q in players.values():
			if not q.down and q.wp.distance_to(p.wp) < 62.0:
				helped = true
		p.revive = clampf(p.revive + (delta / 2.5 if helped else -delta / 2.0), 0.0, 1.0)
		if p.revive >= 1.0:
			p.down = false
			p.hp = 2
			p.host_inv_t = 1.5
			p.revive = 0.0
			ev_all("revive", [p.slot])

func nearest_player(wp: Vector2) -> Variant:
	var best = null
	var bd := 1e9
	for p in players.values():
		if p.down:
			continue
		var d: float = p.wp.distance_squared_to(wp)
		if d < bd:
			bd = d
			best = p
	return best

func speed_mult() -> float:
	return 1.0 + 0.04 * maxi(0, room_index)

func bot_goal(p) -> Variant:
	if not p.picked and pedestals.size() > 0:
		return pedestals[p.slot % pedestals.size()].wp
	if door_open and room:
		return room.door_pos() + Vector2(0, 26)
	return null

# ------------------------------------------------------------------ ennemis et tirs (hôte)
func spawn_enemy(kind: String, wp: Vector2) -> void:
	var n := maxi(1, players.size())
	var mult := (1.0 + 0.6 * (n - 1)) * (1.0 + 0.12 * maxi(0, room_index))
	if not EnemyScript.DEF[kind].has("boss"):
		mult = 1.0 + 0.25 * (n - 1) + 0.1 * maxi(0, room_index)
	var e := _make_enemy(next_id, kind)
	next_id += 1
	e.host = true
	e.setup(kind, wp, mult)

func _make_enemy(id: int, kind: String) -> Node2D:
	var e := Node2D.new()
	e.set_script(EnemyScript)
	e.game = self
	e.id = id
	e.kind = kind
	enemies[id] = e
	ents.add_child(e)
	return e

func spawn_shot(kind: String, wp: Vector2, vel: Vector2, owner_slot: int) -> void:
	var s := _make_shot(next_id, kind)
	next_id += 1
	s.host = true
	s.wp = wp
	s.vel = vel
	s.owner_slot = owner_slot
	if kind == "soul":
		s.life = 0.75
	if kind == "spore":
		Audio.sfx("spit")

func _make_shot(id: int, kind: String) -> Node2D:
	var s := Node2D.new()
	s.set_script(ShotScript)
	s.game = self
	s.id = id
	s.kind = kind
	if kind in ["ring", "ring2"]:
		s.z_index = -5
		s.z_as_relative = false
	shots[id] = s
	ents.add_child(s)
	return s

func hurt_player(p, dmg: int, from: Vector2, parryable: bool) -> String:
	if p.down or p.is_inv() or opt_god:
		return "miss"
	if parryable and p.is_parrying():
		p.soul = mini(PlayerScript.SOUL_MAX, p.soul + 11)
		ev_all("parry", [p.slot])
		return "parried"
	p.hp -= dmg
	p.host_inv_t = 1.0
	var k: Vector2 = (p.wp - from).normalized()
	ev_all("hurt", [p.slot, k.x, k.y])
	if p.has("coquille"):
		for e in enemies.values():
			if e.wp.distance_to(p.wp) < 80.0 + e.radius():
				damage_enemy(e, 2, p.wp, -1, false)
	if p.hp <= 0:
		p.hp = 0
		p.down = true
		p.revive = 0.0
		ev_all("down", [p.slot])
	return "hit"

func damage_enemy(e, dmg: int, from: Vector2, slot: int, melee: bool) -> void:
	if not e.take_hit(dmg, from):
		return
	ev_all("hit", [e.wp.x, e.wp.y])
	if melee and players.has(slot):
		var p = players[slot]
		p.soul = mini(PlayerScript.SOUL_MAX, p.soul + (18 if p.has("ame") else 11))
	if e.hp <= 0:
		shards += int(EnemyScript.DEF[e.kind]["shards"])
		ev_all("kill", [e.wp.x, e.wp.y, e.is_boss()])
		enemies.erase(e.id)
		e.queue_free()

# ------------------------------------------------------------------ actions des joueurs
func act(slot: int, kind: String, dir: Vector2, combo: int) -> void:
	rpc("r_act", slot, kind, dir.x, dir.y, combo)

@rpc("any_peer", "call_local", "reliable")
func r_act(slot: int, kind: String, dx: float, dy: float, combo: int) -> void:
	if not players.has(slot) or not _owns(multiplayer.get_remote_sender_id(), slot):
		return
	var p = players[slot]
	var dir := Vector2(dx, dy).normalized()
	if p.down:
		return
	p.on_act(kind, dir, combo)
	if not is_host():
		return
	match kind:
		"atk":
			var reach: float = p.reach() * (1.25 if combo == 2 else 1.0)
			var half := 1.6 if combo == 2 else 1.05
			var dmg: int = p.damage() + (1 if combo == 2 else 0)
			for e in enemies.values():
				var v: Vector2 = e.wp - p.wp
				if v.length() - e.radius() < reach and (v.length() < 22.0 or absf(dir.angle_to(v)) < half):
					damage_enemy(e, dmg, p.wp, slot, true)
			for s in shots.values():
				if s.kind == "spore" and s.wp.distance_to(p.wp) < reach and absf(dir.angle_to(s.wp - p.wp)) < half:
					s.dead = true
		"spell":
			if p.soul >= PlayerScript.SOUL_COST:
				p.soul -= PlayerScript.SOUL_COST
				spawn_shot("soul", p.wp + dir * 20.0, dir * 620.0, slot)
		"heal":
			if p.soul >= PlayerScript.SOUL_COST and p.hp < p.max_hp:
				p.soul -= PlayerScript.SOUL_COST
				p.hp += 1

func send_pstate(p) -> void:
	if online:
		rpc("r_pstate", p.slot, p.wp.x, p.wp.y, p.aim.x, p.aim.y, p.flags)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func r_pstate(slot: int, x: float, y: float, ax: float, ay: float, fl: int) -> void:
	if not players.has(slot) or not _owns(multiplayer.get_remote_sender_id(), slot):
		return
	var p = players[slot]
	if p.local:
		return
	p.target_wp = Vector2(x, y)
	p.aim = Vector2(ax, ay)
	p.flags = fl

# ------------------------------------------------------------------ état du monde (hôte -> invités)
func _snapshot() -> Dictionary:
	var pl := []
	for p in players.values():
		pl.append([p.slot, p.hp, p.max_hp, p.soul, p.down, p.revive, p.picked, p.host_inv_t > 0.0])
	var en := []
	for e in enemies.values():
		en.append([e.id, e.kind, e.wp.x, e.wp.y, e.hp, e.max_hp, e.state, e.t, e.face.x, e.face.y, e.stun_t, e.tgt.x, e.tgt.y, e.phase2])
	var sh := []
	for s in shots.values():
		sh.append([s.id, s.kind, s.wp.x, s.wp.y, s.vel.x, s.vel.y, s.r])
	var pb := []
	for ped in pedestals:
		pb.append([ped.boon, ped.progress])
	return {"p": pl, "e": en, "s": sh, "sh": shards, "pb": pb, "door": door_open, "dc": [door_count.x, door_count.y], "ph": phase}

@rpc("authority", "call_remote", "unreliable_ordered")
func r_snap(d: Dictionary) -> void:
	if room == null or ents == null:
		return
	shards = d["sh"]
	phase = d["ph"]
	door_count = Vector2i(d["dc"][0], d["dc"][1])
	if d["door"] != door_open:
		door_open = d["door"]
		room.door_open = door_open
		room.queue_redraw()
	for a in d["p"]:
		if players.has(a[0]):
			var p = players[a[0]]
			p.hp = a[1]
			p.max_hp = a[2]
			p.soul = a[3]
			p.down = a[4]
			p.revive = a[5]
			p.picked = a[6]
			if not p.local:
				p.host_inv_t = 0.1 if a[7] else 0.0
	var seen := {}
	for a in d["e"]:
		seen[a[0]] = true
		var e = enemies.get(a[0])
		if e == null:
			e = _make_enemy(a[0], a[1])
			e.wp = Vector2(a[2], a[3])
		e.target_wp = Vector2(a[2], a[3])
		e.hp = a[4]
		e.max_hp = a[5]
		e.state = a[6]
		e.t = a[7]
		e.face = Vector2(a[8], a[9])
		e.stun_t = a[10]
		e.tgt = Vector2(a[11], a[12])
		e.phase2 = a[13]
	for id in enemies.keys():
		if not seen.has(id):
			enemies[id].queue_free()
			enemies.erase(id)
	seen = {}
	for a in d["s"]:
		seen[a[0]] = true
		var s = shots.get(a[0])
		if s == null:
			s = _make_shot(a[0], a[1])
		s.kind = a[1]
		s.wp = Vector2(a[2], a[3])
		s.vel = Vector2(a[4], a[5])
		s.r = a[6]
	for id in shots.keys():
		if not seen.has(id):
			shots[id].queue_free()
			shots.erase(id)
	var pb: Array = d["pb"]
	if pb.size() != pedestals.size():
		var ids := []
		for a in pb:
			ids.append(a[0])
		_set_pedestals(ids)
	for i in pb.size():
		pedestals[i].progress = pb[i][1]

# ------------------------------------------------------------------ évènements (hôte -> tous)
func ev_all(kind: String, args: Array) -> void:
	rpc("r_ev", kind, args)

func fx_all(kind: String, wp: Vector2, col: Color) -> void:
	ev_all("fx", [kind, wp.x, wp.y, col])

func shake_all(a: float) -> void:
	ev_all("shake", [a])

@rpc("authority", "call_local", "reliable")
func r_ev(kind: String, a: Array) -> void:
	match kind:
		"hurt":
			if players.has(a[0]):
				players[a[0]].on_hurt(Vector2(a[1], a[2]))
		"parry":
			if players.has(a[0]):
				fx("parry", players[a[0]].wp, Color(1, 1, 1))
				Audio.sfx("parry")
		"down":
			Audio.sfx("hurt", 0.02, 0.0)
			shake(5.0)
		"revive":
			if players.has(a[0]):
				fx("heal", players[a[0]].wp, players[a[0]].color())
				Audio.sfx("heal")
		"hit":
			fx("hit", Vector2(a[0], a[1]), Color(1, 1, 1))
			Audio.sfx("hit")
		"kill":
			fx("death", Vector2(a[0], a[1]), Color(1.0, 0.9, 0.7))
			Audio.sfx("kill")
			if a[2]:
				shake(12.0)
		"block":
			fx("block", Vector2(a[0], a[1]), Color(1, 1, 1))
			Audio.sfx("parry", 0.1, -8.0)
		"door":
			Audio.sfx("door")
		"pick":
			if players.has(a[0]):
				fx("pick", players[a[0]].wp, BOONS[a[1]]["col"])
				Audio.sfx("pickup")
				if players[a[0]].local:
					banner = BOONS[a[1]]["name"]
					banner_t = 2.0
		"banner":
			banner = a[0]
			banner_t = a[1]
		"fx":
			fx(a[0], Vector2(a[1], a[2]), a[3])
		"shake":
			shake(a[0])

func fx(kind: String, wp: Vector2, col: Color) -> void:
	if ents == null:
		return
	var f := Node2D.new()
	f.set_script(FxScript)
	f.kind = kind
	f.col = col
	f.position = Iso.to_screen(wp)
	f.z_index = 5
	ents.add_child(f)

func shake(a: float) -> void:
	shake_amt = maxf(shake_amt, a)

# ------------------------------------------------------------------ ouverture automatique du port (UPnP)
var upnp_state := ""      # "", "search", "ok", "fail"
var public_ip := ""
var _upnp_thread: Thread

func start_upnp() -> void:
	if _upnp_thread != null or DisplayServer.get_name() == "headless":
		return
	upnp_state = "search"
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work)

func _upnp_work() -> void:
	var u := UPNP.new()
	var ok := false
	var ip := ""
	if u.discover(2500, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS:
		var gw := u.get_gateway()
		if gw and gw.is_valid_gateway():
			if u.add_port_mapping(PORT, PORT, "La Ronde des Veilleurs", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
				ok = true
				ip = u.query_external_address()
	_upnp_done.call_deferred(ok, ip)

func _upnp_done(ok: bool, ip: String) -> void:
	upnp_state = "ok" if ok else "fail"
	public_ip = ip
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null

func toggle_pause() -> void:
	if mode == "menu":
		return
	if menu.screen == "pause":
		solo_pause = false
		menu.show_screen("lobby" if mode == "lobby" else "none")
	else:
		solo_pause = not online
		menu.show_screen("pause")

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_ESCAPE:
			toggle_pause()
		elif ev.physical_keycode == KEY_ENTER and mode == "lobby" and menu.screen == "lobby":
			host_start_run()
		elif ev.physical_keycode == KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif ev is InputEventJoypadButton and ev.pressed:
		if ev.button_index == JOY_BUTTON_BACK and mode == "lobby" and ev.device in local_devices.values() or (ev.button_index == JOY_BUTTON_BACK and mode == "lobby" and ev.device == 0 and local_devices.get(0, "") == "any"):
			host_start_run()

# Adresses de cette machine sur le réseau local (affichées à l'hôte).
func local_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out
