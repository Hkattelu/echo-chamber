extends Node2D
## ECHO CHAMBER — 2D isometric temporal-puzzle prototype.
## Turn-based: every action (move or wait) advances ONE global tick. When you bank
## a run, your recorded path becomes an Echo clone that replays in lockstep. You cannot
## collide with echoes (ghosts), but they DO press pressure plates. The exit opens only
## while ALL plates are held at the same tick, so stacking echoes is mandatory.
## Tiles can have per-cell elevation; you may step up/down at most `max_climb` levels.
## Sprites load at runtime from res://assets/sprites/ with a procedural fallback.

# ---- Tunable game-feel knobs (live-editable in the Inspector) ----
@export var tile_w: int = 96
@export var tile_h: int = 48
@export var wall_height: int = 38
@export var level_step: int = 22      # screen px of vertical rise per elevation level
@export var max_climb: int = 1        # how many levels you can step up/down in one move
@export var move_time: float = 0.11
@export var echo_alpha: float = 0.6

# ---- Palette (fallback shapes + state glows + platform columns) ----
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

const TokenScript := preload("res://scripts/Token.gd")

const SPR := {
	"floor_a": {"path": "res://assets/sprites/floor_a.png", "anchor": Vector2(48, 32)},
	"floor_b": {"path": "res://assets/sprites/floor_b.png", "anchor": Vector2(48, 32)},
	"wall":    {"path": "res://assets/sprites/wall.png",    "anchor": Vector2(48, 60)},
	"plate":   {"path": "res://assets/sprites/plate.png",   "anchor": Vector2(36, 22)},
	"exit":    {"path": "res://assets/sprites/exit.png",    "anchor": Vector2(44, 30)},
	"pawn":    {"path": "res://assets/sprites/pawn.png",    "anchor": Vector2(22, 56)},
}
var tex := {}

# ---- Levels ( # wall, . floor, P start, E exit, 1-9 plates ).
#      Optional parallel "heights" grid: digit = elevation level per cell. ----
var levels := [
	{
		"name": "First Echo",
		"rows": [
			"########",
			"#......#",
			"#.1..E.#",
			"#......#",
			"#..P...#",
			"#......#",
			"#......#",
			"########"],
		"heights": [
			"00000000",
			"00000000",
			"00000200",
			"00000100",
			"00000000",
			"00000000",
			"00000000",
			"00000000"],
	},
	{
		"name": "Twin Pressure",
		"rows": [
			"#########",
			"#...E...#",
			"#.1...2.#",
			"#.......#",
			"#...P...#",
			"#.......#",
			"#.......#",
			"#########"],
		"heights": [
			"000000000",
			"011121110",
			"011111110",
			"000000000",
			"000000000",
			"000000000",
			"000000000",
			"000000000"],
	},
	{
		"name": "Triad",
		"rows": [
			"###########",
			"#....E....#",
			"#.1.....3.#",
			"#.........#",
			"#....P....#",
			"#.........#",
			"#....2....#",
			"###########"],
		"heights": [
			"00000000000",
			"01100200110",
			"01100100110",
			"00000000000",
			"00000000000",
			"00000000000",
			"00000000000",
			"00000000000"],
	},
]

# ---- Level state ----
var level_index := 0
var level_name := ""
var grid_w := 0
var grid_h := 0
var walls := {}
var floors := {}
var heights := {}
var plates: Array[Vector2i] = []
var exit_cell := Vector2i.ZERO
var start_cell := Vector2i.ZERO
var board_offset := Vector2.ZERO

# ---- Run state ----
var tick := 0
var player_cell := Vector2i.ZERO
var current_path: Array = []
var echoes: Array = []
var pressed_plates := {}
var exit_open := false
var won := false
var busy := false

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
	var rows: Array = data["rows"]
	var hrows: Array = data.get("heights", [])
	walls.clear(); floors.clear(); heights.clear(); plates.clear()
	for t in echo_tokens:
		t.queue_free()
	echo_tokens.clear(); echoes.clear()
	won = false; banner.visible = false
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
				"1", "2", "3", "4", "5", "6", "7", "8", "9": plates.append(cell)
	var center := Vector2((grid_w - 1) * 0.5, (grid_h - 1) * 0.5)
	var raw := Vector2((center.x - center.y) * tile_w * 0.5, (center.x + center.y) * tile_h * 0.5)
	var vp := get_viewport_rect().size
	board_offset = vp * 0.5 - raw + Vector2(0, -wall_height * 0.5 + 24)
	_reset_run(false)

func _reset_run(bank: bool) -> void:
	if bank and tick > 0:
		echoes.append({"path": current_path.duplicate()})
		var et := _make_token(C_ECHO, echo_alpha, str(echoes.size()), C_ECHO_TINT)
		et.z_index = 50
		echo_tokens.append(et)
	tick = 0
	player_cell = start_cell
	current_path = [start_cell]
	won = false; banner.visible = false
	_place_tokens_instant()
	_update_state()
	_update_hud()

func _full_reset() -> void:
	load_level(level_index)

func _next_level() -> void:
	load_level((level_index + 1) % levels.size())

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
		KEY_UP, KEY_W: _do_move(Vector2i(0, -1))
		KEY_RIGHT, KEY_D: _do_move(Vector2i(1, 0))
		KEY_DOWN, KEY_S: _do_move(Vector2i(0, 1))
		KEY_LEFT, KEY_A: _do_move(Vector2i(-1, 0))
		KEY_SPACE: _advance(player_cell)
		KEY_R, KEY_ENTER, KEY_KP_ENTER: _reset_run(true)
		KEY_Q: _reset_run(false)

func _do_move(delta: Vector2i) -> void:
	var target := player_cell + delta
	if not _walkable(target):
		return
	_advance(target)

func _advance(new_cell: Vector2i) -> void:
	player_cell = new_cell
	tick += 1
	current_path.append(player_cell)
	busy = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(player_token, "position", _surface(player_cell), move_time)
	for i in range(echoes.size()):
		tw.tween_property(echo_tokens[i], "position", _surface(_echo_pos(echoes[i], tick)), move_time)
	tw.finished.connect(_on_move_done, CONNECT_ONE_SHOT)
	_update_hud()

func _on_move_done() -> void:
	busy = false
	_update_state()
	_check_win()
	_update_hud()

func _walkable(cell: Vector2i) -> bool:
	if not floors.has(cell):
		return false
	if absi(_height(cell) - _height(player_cell)) > max_climb:
		return false
	return true

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

# ---- Iso transform (ground = no elevation, surface = raised by cell height) ----
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
			var beam := 78.0
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-bw, 0), c + Vector2(bw, 0),
				c + Vector2(bw * 0.55, -beam), c + Vector2(-bw * 0.55, -beam)]),
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
	var run_len: int = current_path.size() - 1
	var exit_str := "OPEN" if exit_open else "closed"
	var lines := []
	lines.append("ECHO CHAMBER   Level %d/%d — %s" % [level_index + 1, levels.size(), level_name])
	lines.append("Echoes: %d   Plates held: %d/%d   Exit: %s   Tick: %d  (run length: %d)" % [echoes.size(), pressed_count, plates.size(), exit_str, tick, run_len])
	lines.append("")
	lines.append("Move: Arrows / WASD (step up/down 1 level)    Wait: Space")
	lines.append("R / Enter: bank run as echo + restart    Q: redo run (no echo)")
	lines.append("T: reset level    N: next level (after solving)    Esc: title")
	lines.append("")
	lines.append("Goal: hold ALL plates at once, then reach the raised portal.")
	hud.text = "\n".join(lines)
