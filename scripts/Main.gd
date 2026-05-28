extends Node2D
## ECHO CHAMBER — 2D isometric temporal-puzzle prototype.
##
## Core loop: the game is turn-based. Every action you take (move or wait) advances
## ONE global tick. When you "bank" a run, your recorded path becomes an Echo clone
## that replays its actions in lockstep with you on the next attempt. You cannot
## collide with echoes (they are ghosts), but they DO press pressure plates.
## The exit opens only while ALL plates are held at the same tick — so multi-plate
## levels are impossible without stacking echoes.

# -------------------------------------------------------------------------
# Tunable game-feel knobs (safe to tweak live in the Inspector)
# -------------------------------------------------------------------------
@export var tile_w: int = 96            # iso tile width in px (2:1 ratio looks right with tile_h = tile_w/2)
@export var tile_h: int = 48            # iso tile height in px
@export var wall_height: int = 38       # how tall wall blocks rise
@export var move_time: float = 0.11     # seconds to slide between tiles (lower = snappier)
@export var echo_alpha: float = 0.55    # transparency of echo clones (readability vs. clutter)

# -------------------------------------------------------------------------
# Palette
# -------------------------------------------------------------------------
const C_BG := Color("11131c")
const C_FLOOR := Color("3a4a63")
const C_FLOOR_EDGE := Color("2a3650")
const C_WALL_TOP := Color("6b7a99")
const C_WALL_L := Color("46536e")
const C_WALL_R := Color("38445c")
const C_PLATE := Color("d99a2b")
const C_PLATE_ON := Color("4fd66a")
const C_EXIT := Color("5b3b8c")
const C_EXIT_ON := Color("33e0e0")
const C_PLAYER := Color("ffd23f")
const C_ECHO := Color("46c9ff")

const TokenScript := preload("res://scripts/Token.gd")

# -------------------------------------------------------------------------
# Level definitions  ( # wall, . floor, P start, E exit, 1-9 pressure plates )
# Plate count == echoes required, so difficulty escalates cleanly.
# -------------------------------------------------------------------------
var levels := [
	{
		"name": "First Echo",
		"rows": [
			"#######",
			"#.....#",
			"#..1..#",
			"#.....#",
			"#..P..#",
			"#.....#",
			"#..E..#",
			"#######",
		],
	},
	{
		"name": "Twin Pressure",
		"rows": [
			"#########",
			"#.......#",
			"#.1...2.#",
			"#.......#",
			"#...P...#",
			"#.......#",
			"#...E...#",
			"#########",
		],
	},
	{
		"name": "Triad",
		"rows": [
			"###########",
			"#....3....#",
			"#.1.....2.#",
			"#.........#",
			"#....P....#",
			"#.........#",
			"#....E....#",
			"###########",
		],
	},
]

# -------------------------------------------------------------------------
# Level state
# -------------------------------------------------------------------------
var level_index := 0
var level_name := ""
var grid_w := 0
var grid_h := 0
var walls := {}                 # Vector2i -> true
var floors := {}                # Vector2i -> true (walkable cells)
var plates: Array[Vector2i] = []
var exit_cell := Vector2i.ZERO
var start_cell := Vector2i.ZERO
var board_offset := Vector2.ZERO

# -------------------------------------------------------------------------
# Run state
# -------------------------------------------------------------------------
var tick := 0                   # global tick of the current attempt
var player_cell := Vector2i.ZERO
var current_path: Array = []    # Array[Vector2i] — index == tick, [0] == start
var echoes: Array = []          # Array of { "path": Array[Vector2i] }
var pressed_plates := {}        # Vector2i -> bool (this tick)
var exit_open := false
var won := false
var busy := false               # input locked while tokens slide

# -------------------------------------------------------------------------
# Nodes
# -------------------------------------------------------------------------
var player_token: Node2D
var echo_tokens: Array = []     # parallel to `echoes`
var hud: Label
var banner: Label

# -------------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------------
func _ready() -> void:
	_build_hud()
	player_token = _make_token(C_PLAYER, 1.0, "")
	player_token.z_index = 100
	load_level(0)

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)

	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_color", Color("d7e2f0"))
	hud.add_theme_constant_override("outline_size", 4)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
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

# -------------------------------------------------------------------------
# Level loading
# -------------------------------------------------------------------------
func load_level(idx: int) -> void:
	level_index = idx
	var data: Dictionary = levels[idx]
	level_name = data["name"]
	var rows: Array = data["rows"]

	# Reset containers.
	walls.clear()
	floors.clear()
	plates.clear()
	for t in echo_tokens:
		t.queue_free()
	echo_tokens.clear()
	echoes.clear()
	won = false
	banner.visible = false

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
			match ch:
				"P": start_cell = cell
				"E": exit_cell = cell
				"1", "2", "3", "4", "5", "6", "7", "8", "9": plates.append(cell)

	# Center the board in the viewport (lift slightly for wall height + HUD).
	var center := Vector2((grid_w - 1) * 0.5, (grid_h - 1) * 0.5)
	var raw := Vector2((center.x - center.y) * tile_w * 0.5, (center.x + center.y) * tile_h * 0.5)
	var vp := get_viewport_rect().size
	board_offset = vp * 0.5 - raw + Vector2(0, -wall_height * 0.5 + 10)

	_reset_run(false)

# -------------------------------------------------------------------------
# Run control
# -------------------------------------------------------------------------
func _reset_run(bank: bool) -> void:
	if bank and tick > 0:
		echoes.append({ "path": current_path.duplicate() })
		var et := _make_token(C_ECHO, echo_alpha, str(echoes.size()))
		et.z_index = 50
		echo_tokens.append(et)

	tick = 0
	player_cell = start_cell
	current_path = [start_cell]
	won = false
	banner.visible = false

	_place_tokens_instant()
	_update_state()
	_update_hud()

func _full_reset() -> void:
	load_level(level_index)

func _next_level() -> void:
	load_level((level_index + 1) % levels.size())

# -------------------------------------------------------------------------
# Input
# -------------------------------------------------------------------------
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode

	# Meta keys work even while busy / won.
	match k:
		KEY_T, KEY_BACKSPACE:
			_full_reset(); return
		KEY_N:
			if won: _next_level()
			return
		KEY_ESCAPE:
			get_tree().quit(); return

	if won or busy:
		return

	match k:
		# Movement: arrow keys / WASD map to the four isometric diagonals.
		KEY_UP, KEY_W: _do_move(Vector2i(0, -1))     # NE (up-right)
		KEY_RIGHT, KEY_D: _do_move(Vector2i(1, 0))   # SE (down-right)
		KEY_DOWN, KEY_S: _do_move(Vector2i(0, 1))    # SW (down-left)
		KEY_LEFT, KEY_A: _do_move(Vector2i(-1, 0))   # NW (up-left)
		KEY_SPACE: _advance(player_cell)             # wait one tick
		KEY_R, KEY_ENTER, KEY_KP_ENTER: _reset_run(true)  # bank run as echo
		KEY_Q: _reset_run(false)                     # discard run, replay echoes

func _do_move(delta: Vector2i) -> void:
	var target := player_cell + delta
	if not _walkable(target):
		return  # bonk a wall: ignored, no tick consumed (prevents accidental desync)
	_advance(target)

# Apply one tick: player goes to `new_cell`, all echoes step, then slide visuals.
func _advance(new_cell: Vector2i) -> void:
	player_cell = new_cell
	tick += 1
	current_path.append(player_cell)

	busy = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(player_token, "position", _cell_to_screen(player_cell), move_time)
	for i in range(echoes.size()):
		var dest := _cell_to_screen(_echo_pos(echoes[i], tick))
		tw.tween_property(echo_tokens[i], "position", dest, move_time)
	tw.finished.connect(_on_move_done, CONNECT_ONE_SHOT)
	_update_hud()

func _on_move_done() -> void:
	busy = false
	_update_state()
	_check_win()
	_update_hud()

# -------------------------------------------------------------------------
# Simulation helpers
# -------------------------------------------------------------------------
func _walkable(cell: Vector2i) -> bool:
	return floors.has(cell)

func _echo_pos(echo: Dictionary, t: int) -> Vector2i:
	var p: Array = echo["path"]
	return p[clamp(t, 0, p.size() - 1)]

# Recompute which cells are occupied this tick → plate/exit state.
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

	exit_open = all_on  # (true with zero plates, but every level has plates)
	queue_redraw()

func _check_win() -> void:
	if not won and exit_open and player_cell == exit_cell:
		won = true
		if level_index == levels.size() - 1:
			banner.text = "ALL CHAMBERS CLEARED!   N = restart from Level 1"
		else:
			banner.text = "CHAMBER SOLVED!   N = next level"
		banner.visible = true

# -------------------------------------------------------------------------
# Tokens
# -------------------------------------------------------------------------
func _make_token(col: Color, a: float, label: String) -> Node2D:
	var t := Node2D.new()
	t.set_script(TokenScript)
	add_child(t)
	t.setup(col, a, label)
	return t

func _place_tokens_instant() -> void:
	player_token.position = _cell_to_screen(player_cell)
	for i in range(echoes.size()):
		echo_tokens[i].position = _cell_to_screen(_echo_pos(echoes[i], tick))

# -------------------------------------------------------------------------
# Iso coordinate transform
# -------------------------------------------------------------------------
func _cell_to_screen(c: Vector2i) -> Vector2:
	return Vector2((c.x - c.y) * tile_w * 0.5, (c.x + c.y) * tile_h * 0.5) + board_offset

func _diamond(center: Vector2, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -h * 0.5),
		center + Vector2(w * 0.5, 0),
		center + Vector2(0, h * 0.5),
		center + Vector2(-w * 0.5, 0),
	])

# -------------------------------------------------------------------------
# Rendering (back-to-front by x+y for correct iso overlap)
# -------------------------------------------------------------------------
func _draw() -> void:
	# Background.
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
	var c := _cell_to_screen(cell)
	var dia := _diamond(c, tile_w, tile_h)
	draw_colored_polygon(dia, C_FLOOR)
	var outline := dia.duplicate()
	outline.append(dia[0])
	draw_polyline(outline, C_FLOOR_EDGE, 2.0)

	if plates.has(cell):
		var on: bool = pressed_plates.get(cell, false)
		var col := C_PLATE_ON if on else C_PLATE
		var inner := _diamond(c, tile_w * 0.6, tile_h * 0.6)
		draw_colored_polygon(inner, col)
		var ring := inner.duplicate()
		ring.append(inner[0])
		draw_polyline(ring, col.darkened(0.3), 2.0)

	if cell == exit_cell:
		var ecol := C_EXIT_ON if exit_open else C_EXIT
		# Concentric diamonds to read as a portal.
		draw_colored_polygon(_diamond(c, tile_w * 0.78, tile_h * 0.78), ecol.darkened(0.35))
		draw_colored_polygon(_diamond(c, tile_w * 0.52, tile_h * 0.52), ecol)
		draw_colored_polygon(_diamond(c, tile_w * 0.26, tile_h * 0.26), ecol.lightened(0.4))

func _draw_wall(cell: Vector2i) -> void:
	var base := _cell_to_screen(cell)
	var top := base - Vector2(0, wall_height)
	var b := _diamond(base, tile_w, tile_h)   # ground diamond
	var t := _diamond(top, tile_w, tile_h)    # top diamond
	# b/t order: [top, right, bottom, left]
	# Left face (between left & bottom corners).
	draw_colored_polygon(PackedVector2Array([t[3], t[2], b[2], b[3]]), C_WALL_L)
	# Right face (between bottom & right corners).
	draw_colored_polygon(PackedVector2Array([t[2], t[1], b[1], b[2]]), C_WALL_R)
	# Top face.
	draw_colored_polygon(t, C_WALL_TOP)
	var outline := t.duplicate()
	outline.append(t[0])
	draw_polyline(outline, C_WALL_TOP.darkened(0.4), 2.0)

# -------------------------------------------------------------------------
# HUD
# -------------------------------------------------------------------------
func _update_hud() -> void:
	var pressed_count := 0
	for p in plates:
		if pressed_plates.get(p, false):
			pressed_count += 1

	var run_len: int = current_path.size() - 1
	var exit_str := "OPEN" if exit_open else "closed"

	var lines := []
	lines.append("ECHO CHAMBER   Level %d/%d — %s" % [level_index + 1, levels.size(), level_name])
	lines.append("Echoes: %d   Plates held: %d/%d   Exit: %s   Tick: %d  (run length: %d)" % [
		echoes.size(), pressed_count, plates.size(), exit_str, tick, run_len])
	lines.append("")
	lines.append("Move: Arrows / WASD (isometric diagonals)    Wait: Space")
	lines.append("R / Enter: bank this run as an echo + restart    Q: redo run (no echo)")
	lines.append("T: reset level    N: next level (after solving)    Esc: quit")
	lines.append("")
	lines.append("Goal: hold ALL plates at once, then step onto the portal.")
	hud.text = "\n".join(lines)
