extends Node2D
## ECHO CHAMBER — 2D isometric temporal-puzzle prototype ("Phase Exchange").
##
## Turn-based, deterministic lockstep. Two player states:
##   PHYSICAL — tangible. Walls block you, hazards kill you. This is how you actually
##              reach the exit. From here you can SWAP positions with a ghost.
##   PHASE    — intangible (recording a ghost). You start at the level start, walk
##              THROUGH walls and over hazards, then COMMIT: you snap back to start and
##              a Ghost spawns that replays that exact (wall-phasing) path in lockstep.
## Ghosts are non-colliding phase clones; they press plates. The exit opens only while
## ALL plates are held in the same tick. SWAP turns a ghost's phased position into your
## physical one — the only way to reach sealed rooms or cross hazard pits.
##
## Determinism: every attempt runs from tick 0; entering phase / committing / dying all
## restart the attempt at tick 0 with all ghosts replaying from 0. (See CLAUDE.md.)
## Sprites load at runtime from res://assets/sprites/ with a procedural fallback.

# ---- Tunable game-feel knobs (live-editable in the Inspector) ----
@export var tile_w: int = 96
@export var tile_h: int = 48
@export var wall_height: int = 38
@export var level_step: int = 22
@export var max_climb: int = 1
@export var move_time: float = 0.11
@export var echo_alpha: float = 0.6
@export var phase_alpha: float = 0.5     # translucency of the live player while phasing

# ---- Palette ----
const C_BG := Color("11131c")
const C_FLOOR := Color("3a4a63")
const C_FLOOR_EDGE := Color("2a3650")
const C_WALL_TOP := Color("6b7a99")
const C_WALL_L := Color("46536e")
const C_WALL_R := Color("38445c")
const C_COL_L := Color("4a5a4e")
const C_COL_R := Color("36443a")
const C_PLATE := Color("d99a2b")
const C_PLATE_ON := Color("4fd66a")
const C_EXIT := Color("5b3b8c")
const C_EXIT_ON := Color("33e0e0")
const C_PLAYER := Color("ffd23f")
const C_ECHO := Color("46c9ff")
const C_ECHO_TINT := Color(0.55, 0.82, 1.0)
const C_PHASE_TINT := Color(0.7, 0.9, 1.0)

const TokenScript := preload("res://scripts/Token.gd")

const SPR := {
	"floor_a": {"path": "res://assets/sprites/floor_a.png", "anchor": Vector2(48, 32)},
	"floor_b": {"path": "res://assets/sprites/floor_b.png", "anchor": Vector2(48, 32)},
	"wall":    {"path": "res://assets/sprites/wall.png",    "anchor": Vector2(48, 60)},
	"plate":   {"path": "res://assets/sprites/plate.png",   "anchor": Vector2(36, 22)},
	"exit":    {"path": "res://assets/sprites/exit.png",    "anchor": Vector2(44, 30)},
	"hazard":  {"path": "res://assets/sprites/hazard.png",  "anchor": Vector2(48, 32)},
	"pawn":    {"path": "res://assets/sprites/pawn.png",    "anchor": Vector2(22, 56)},
}
var tex := {}

enum Mode { PHYSICAL, PHASE }

# ---- Levels ( # wall, . floor, P start, E exit, ^ hazard, 1-9 plates ).
#      Optional parallel "heights" grid (digit per cell). ----
var levels := [
	{
		"name": "Ghost Walk",
		"hint": "Phase (F) through the wall onto the switch, Commit (R), then walk to the exit.",
		"rows": [
			"#########",
			"#...P...#",
			"#.......#",
			"#..###..#",
			"#..#1#..#",
			"#..###..#",
			"#...E...#",
			"#########"],
	},
	{
		"name": "Dual Lock",
		"hint": "Two sealed switches need two ghosts. Phase one onto each, then walk down to the exit.",
		"rows": [
			"###########",
			"#....P....#",
			"#.........#",
			"#.###.###.#",
			"#.#1#.#2#.#",
			"#.###.###.#",
			"#.........#",
			"#....E....#",
			"###########"],
	},
	{
		"name": "First Swap",
		"hint": "The exit is sealed. Phase a ghost inside, then Swap (E) to trade places with it.",
		"rows": [
			"#########",
			"#...P...#",
			"#.......#",
			"#..###..#",
			"#..#E#..#",
			"#..###..#",
			"#.......#",
			"#########"],
	},
	{
		"name": "Hazard Crossing",
		"hint": "Spikes kill you, not your ghost. Phase across the pit, then Swap onto the far side.",
		"rows": [
			"#######",
			"#..P..#",
			"#.....#",
			"#^^^^^#",
			"#.....#",
			"#..E..#",
			"#######"],
	},
]

# ---- Level state ----
var level_index := 0
var level_name := ""
var level_hint := ""
var grid_w := 0
var grid_h := 0
var walls := {}
var floors := {}
var hazards := {}
var heights := {}
var plates: Array[Vector2i] = []
var exit_cell := Vector2i.ZERO
var start_cell := Vector2i.ZERO
var board_offset := Vector2.ZERO

# ---- Run state ----
var mode: int = Mode.PHYSICAL
var tick := 0
var player_cell := Vector2i.ZERO
var current_path: Array = []     # recorded only while PHASE
var echoes: Array = []           # Array of { "path": Array[Vector2i] }
var pressed_plates := {}
var exit_open := false
var won := false
var busy := false
var message := ""                # transient status line (death / swap hints)

# ---- Nodes ----
var player_token: Node2D
var echo_tokens: Array = []
var hud: Label
var banner: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()
	_build_hud()
	player_token = _make_token(C_PLAYER, 1.0, "")
	player_token.z_index = 100
	load_level(0)

func _load_textures() -> void:
	for sname in SPR.keys():
		var path: String = SPR[sname]["path"]
		var abs_path := ProjectSettings.globalize_path(path)
		var p := abs_path if FileAccess.file_exists(abs_path) else path
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img != null:
				tex[sname] = ImageTexture.create_from_image(img)

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_color", Color("d7e2f0"))
	hud.add_theme_constant_override("outline_size", 4)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cl.add_child(hud)
	banner = Label.new()
	banner.size = Vector2(1280, 60)
	banner.position = Vector2(0, 300)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 36)
	banner.add_theme_color_override("font_color", Color("ffe66d"))
	banner.add_theme_constant_override("outline_size", 8)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.visible = false
	cl.add_child(banner)

func load_level(idx: int) -> void:
	level_index = idx
	var data: Dictionary = levels[idx]
	level_name = data["name"]
	level_hint = data.get("hint", "")
	var rows: Array = data["rows"]
	var hrows: Array = data.get("heights", [])
	walls.clear(); floors.clear(); hazards.clear(); heights.clear(); plates.clear()
	for t in echo_tokens:
		t.queue_free()
	echo_tokens.clear(); echoes.clear()
	won = false; banner.visible = false; message = ""
	grid_h = rows.size()
	grid_w = (rows[0] as String).length()
	for y in range(grid_h):
		var line: String = rows[y]
		for x in range(line.length()):
			var cell := Vector2i(x, y)
			var ch := line[x]
			if ch == "#":
				walls[cell] = true
				continue
			floors[cell] = true
			var hgt := 0
			if hrows.size() > y and x < (hrows[y] as String).length():
				hgt = (hrows[y] as String)[x].to_int()
			heights[cell] = hgt
			match ch:
				"P": start_cell = cell
				"E": exit_cell = cell
				"^": hazards[cell] = true
				"1", "2", "3", "4", "5", "6", "7", "8", "9": plates.append(cell)
	var center := Vector2((grid_w - 1) * 0.5, (grid_h - 1) * 0.5)
	var raw := Vector2((center.x - center.y) * tile_w * 0.5, (center.x + center.y) * tile_h * 0.5)
	var vp := get_viewport_rect().size
	board_offset = vp * 0.5 - raw + Vector2(0, -wall_height * 0.5 + 24)
	_restart_attempt()

# ---- Attempt / phase control ----
func _restart_attempt() -> void:
	mode = Mode.PHYSICAL
	tick = 0
	player_cell = start_cell
	current_path = [start_cell]
	won = false; banner.visible = false
	_apply_player_look()
	_place_tokens_instant()
	_update_state()
	_update_hud()

func _begin_phase() -> void:
	mode = Mode.PHASE
	tick = 0
	player_cell = start_cell
	current_path = [start_cell]
	message = ""
	_apply_player_look()
	_place_tokens_instant()
	_update_state()
	_update_hud()

func _commit_phase() -> void:
	if current_path.size() > 1:
		echoes.append({"path": current_path.duplicate()})
		var et := _make_token(C_ECHO, echo_alpha, str(echoes.size()), C_ECHO_TINT)
		et.z_index = 50
		echo_tokens.append(et)
		message = "Ghost %d set. Phase again or solve physically." % echoes.size()
	_restart_attempt()

func _cancel_phase() -> void:
	message = "Phase cancelled."
	_restart_attempt()

func _full_reset() -> void:
	load_level(level_index)

func _next_level() -> void:
	load_level((level_index + 1) % levels.size())

func _apply_player_look() -> void:
	var pawn_tex = tex.get("pawn", null)
	if mode == Mode.PHASE:
		var c := (C_PHASE_TINT if pawn_tex != null else C_PLAYER)
		c.a = 1.0
		player_token.setup(c, phase_alpha, "", pawn_tex)
	else:
		var c2 := (Color.WHITE if pawn_tex != null else C_PLAYER)
		c2.a = 1.0
		player_token.setup(c2, 1.0, "", pawn_tex)
	if pawn_tex != null:
		player_token.anchor = SPR["pawn"]["anchor"]

# ---- Input ----
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	match k:
		KEY_T, KEY_BACKSPACE: _full_reset(); return
		KEY_N:
			if won: _next_level()
			return
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://start_screen.tscn"); return
	if won or busy:
		return
	match k:
		KEY_UP, KEY_W: _move(Vector2i(0, -1))
		KEY_RIGHT, KEY_D: _move(Vector2i(1, 0))
		KEY_DOWN, KEY_S: _move(Vector2i(0, 1))
		KEY_LEFT, KEY_A: _move(Vector2i(-1, 0))
		KEY_SPACE: _wait()
		KEY_F:
			if mode == Mode.PHYSICAL: _begin_phase()
			else: _commit_phase()
		KEY_R, KEY_ENTER, KEY_KP_ENTER:
			if mode == Mode.PHASE: _commit_phase()
		KEY_Q:
			if mode == Mode.PHASE: _cancel_phase()
		KEY_E:
			if mode == Mode.PHYSICAL: _swap()

# ---- Movement ----
func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < grid_w and c.y >= 0 and c.y < grid_h

func _phys_walkable(cell: Vector2i) -> bool:
	if not floors.has(cell):
		return false
	return absi(_height(cell) - _height(player_cell)) <= max_climb

func _move(delta: Vector2i) -> void:
	var target := player_cell + delta
	if mode == Mode.PHASE:
		if _in_bounds(target):
			_advance(target, true)
	else:
		if _phys_walkable(target):
			_advance(target, false)

func _wait() -> void:
	_advance(player_cell, mode == Mode.PHASE)

func _swap() -> void:
	if echoes.is_empty():
		message = "No ghost to swap with — Phase (F) one first."
		_update_hud()
		return
	var best := 0
	var bestd := 1.0e20
	for i in range(echoes.size()):
		var gc := _echo_pos(echoes[i], tick)
		var d := (Vector2(gc) - Vector2(player_cell)).length_squared()
		if d < bestd:
			bestd = d; best = i
	message = "Swapped with Ghost %d." % (best + 1)
	_advance(_echo_pos(echoes[best], tick), false)

func _advance(new_cell: Vector2i, record: bool) -> void:
	player_cell = new_cell
	tick += 1
	if record:
		current_path.append(new_cell)
	busy = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(player_token, "position", _surface(player_cell), move_time)
	for i in range(echoes.size()):
		tw.tween_property(echo_tokens[i], "position", _surface(_echo_pos(echoes[i], tick)), move_time)
	tw.finished.connect(_after_step, CONNECT_ONE_SHOT)
	_update_hud()

func _after_step() -> void:
	busy = false
	_update_state()
	if mode == Mode.PHYSICAL:
		if hazards.has(player_cell):
			_die("You hit the spikes! Attempt reset (ghosts kept).")
			return
		_check_win()
	_update_hud()

func _die(msg: String) -> void:
	message = msg
	_restart_attempt()

# ---- Simulation ----
func _height(cell: Vector2i) -> int:
	return heights.get(cell, 0)

func _echo_pos(echo: Dictionary, t: int) -> Vector2i:
	var p: Array = echo["path"]
	return p[clamp(t, 0, p.size() - 1)]

func _update_state() -> void:
	var occupied := {}
	occupied[player_cell] = true
	for e in echoes:
		occupied[_echo_pos(e, tick)] = true
	pressed_plates.clear()
	var all_on := true
	for p in plates:
		var on: bool = occupied.has(p)
		pressed_plates[p] = on
		if not on:
			all_on = false
	exit_open = all_on
	queue_redraw()

func _check_win() -> void:
	if not won and exit_open and player_cell == exit_cell:
		won = true
		if level_index == levels.size() - 1:
			banner.text = "ALL CHAMBERS CLEARED!   N = restart from Level 1"
		else:
			banner.text = "CHAMBER SOLVED!   N = next level"
		banner.visible = true

# ---- Tokens ----
func _make_token(col: Color, a: float, label: String, tint := Color.WHITE) -> Node2D:
	var t := Node2D.new()
	t.set_script(TokenScript)
	add_child(t)
	var pawn_tex = tex.get("pawn", null)
	var draw_col := (tint if pawn_tex != null else col)
	draw_col.a = 1.0
	t.setup(draw_col, a, label, pawn_tex)
	if pawn_tex != null:
		t.anchor = SPR["pawn"]["anchor"]
	return t

func _place_tokens_instant() -> void:
	player_token.position = _surface(player_cell)
	for i in range(echoes.size()):
		echo_tokens[i].position = _surface(_echo_pos(echoes[i], tick))

# ---- Iso transform ----
func _ground(c: Vector2i) -> Vector2:
	return Vector2((c.x - c.y) * tile_w * 0.5, (c.x + c.y) * tile_h * 0.5) + board_offset

func _surface(c: Vector2i) -> Vector2:
	return _ground(c) - Vector2(0, _height(c) * level_step)

func _diamond(center: Vector2, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -h * 0.5), center + Vector2(w * 0.5, 0),
		center + Vector2(0, h * 0.5), center + Vector2(-w * 0.5, 0)])

func _blit(sname: String, pos: Vector2) -> bool:
	if not tex.has(sname):
		return false
	draw_texture(tex[sname], pos - SPR[sname]["anchor"])
	return true

func _draw_column(top: Vector2, depth: float) -> void:
	var t := _diamond(top, tile_w, tile_h)
	var down := Vector2(0, depth)
	draw_colored_polygon(PackedVector2Array([t[3], t[2], t[2] + down, t[3] + down]), C_COL_L)
	draw_colored_polygon(PackedVector2Array([t[2], t[1], t[1] + down, t[2] + down]), C_COL_R)

func _draw() -> void:
	draw_rect(Rect2(Vector2(-4000, -4000), Vector2(8000, 8000)), C_BG)
	for s in range(0, grid_w + grid_h - 1):
		for x in range(grid_w):
			var y := s - x
			if y < 0 or y >= grid_h:
				continue
			var cell := Vector2i(x, y)
			if walls.has(cell):
				_draw_wall(cell)
			elif floors.has(cell):
				_draw_floor(cell)

func _draw_floor(cell: Vector2i) -> void:
	var c := _surface(cell)
	var h := _height(cell)
	if h > 0:
		_draw_column(c, h * level_step)
	if hazards.has(cell):
		if not _blit("hazard", c):
			draw_colored_polygon(_diamond(c, tile_w, tile_h), Color("14181f"))
		return
	var variant := "floor_b" if ((cell.x + cell.y) % 2 == 1) else "floor_a"
	if not _blit(variant, c):
		if not _blit("floor_a", c):
			var dia := _diamond(c, tile_w, tile_h)
			draw_colored_polygon(dia, C_FLOOR)
			var ol := dia.duplicate(); ol.append(dia[0])
			draw_polyline(ol, C_FLOOR_EDGE, 2.0)
	if plates.has(cell):
		if not _blit("plate", c):
			draw_colored_polygon(_diamond(c, tile_w * 0.6, tile_h * 0.6), C_PLATE.darkened(0.2))
		var on: bool = pressed_plates.get(cell, false)
		var glow := C_PLATE_ON if on else C_PLATE
		var ga := 0.55 if on else 0.22
		draw_colored_polygon(_diamond(c, tile_w * 0.5, tile_h * 0.5), Color(glow.r, glow.g, glow.b, ga))
	if cell == exit_cell:
		if not _blit("exit", c):
			draw_colored_polygon(_diamond(c, tile_w * 0.78, tile_h * 0.78), C_EXIT.darkened(0.35))
			draw_colored_polygon(_diamond(c, tile_w * 0.52, tile_h * 0.52), C_EXIT)
		var ecol := C_EXIT_ON if exit_open else C_EXIT
		var ea := 0.7 if exit_open else 0.3
		draw_colored_polygon(_diamond(c, tile_w * 0.4, tile_h * 0.4), Color(ecol.r, ecol.g, ecol.b, ea))
		if exit_open:
			draw_colored_polygon(_diamond(c, tile_w * 0.2, tile_h * 0.2), Color(1, 1, 1, 0.55))
			var bw := tile_w * 0.16
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-bw, 0), c + Vector2(bw, 0),
				c + Vector2(bw * 0.55, -78.0), c + Vector2(-bw * 0.55, -78.0)]),
				Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.16))

func _draw_wall(cell: Vector2i) -> void:
	if _blit("wall", _ground(cell)):
		return
	var base := _ground(cell)
	var top := base - Vector2(0, wall_height)
	var b := _diamond(base, tile_w, tile_h)
	var t := _diamond(top, tile_w, tile_h)
	draw_colored_polygon(PackedVector2Array([t[3], t[2], b[2], b[3]]), C_WALL_L)
	draw_colored_polygon(PackedVector2Array([t[2], t[1], b[1], b[2]]), C_WALL_R)
	draw_colored_polygon(t, C_WALL_TOP)
	var ol := t.duplicate(); ol.append(t[0])
	draw_polyline(ol, C_WALL_TOP.darkened(0.4), 2.0)

func _update_hud() -> void:
	var pressed_count := 0
	for p in plates:
		if pressed_plates.get(p, false):
			pressed_count += 1
	var mode_str := "PHASE (recording — walking through walls)" if mode == Mode.PHASE else "PHYSICAL"
	var lines := []
	lines.append("ECHO CHAMBER   Level %d/%d — %s" % [level_index + 1, levels.size(), level_name])
	lines.append("Mode: %s    Ghosts: %d    Switches: %d/%d    Exit: %s" % [
		mode_str, echoes.size(), pressed_count, plates.size(), ("OPEN" if exit_open else "closed")])
	if level_hint != "":
		lines.append("Hint: " + level_hint)
	if message != "":
		lines.append(">> " + message)
	lines.append("")
	lines.append("Move: Arrows / WASD    Wait: Space")
	lines.append("F: Phase / Commit ghost    Q: cancel phase    E: Swap with ghost")
	lines.append("T: reset level    N: next (after solving)    Esc: title")
	hud.text = "\n".join(lines)
