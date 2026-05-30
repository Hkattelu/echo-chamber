extends Node2D
## ECHO CHAMBER — 2D isometric temporal-puzzle prototype ("Phase Exchange").
## Worn overgrown-tower restyle (Claude Design handoff): mossy stone, Portal palette
## (orange player, purple phase-ghost, teal switches/gate), heavy vignette, minimal HUD.
##
## Turn-based, deterministic lockstep. PHYSICAL (tangible: walls block, hazards kill) is how
## you reach the exit; PHASE (intangible, recording) walks through walls/hazards then commits
## a ghost that replays in lockstep. SWAP (E) teleports you to the nearest ghost. See CLAUDE.md.

# ---- Tunable game-feel knobs ----
@export var tile_w: int = 96
@export var tile_h: int = 48
@export var wall_height: int = 38
@export var level_step: int = 22
@export var max_climb: int = 1
@export var move_time: float = 0.11
@export var echo_alpha: float = 0.62
@export var phase_alpha: float = 0.5

# ---- Palette (worn overgrown tower, mossy) ----
const C_FLOOR := Color("9ea08d")
const C_FLOOR_EDGE := Color("585a47")
const C_WALL_TOP := Color("8b8d78")
const C_WALL_L := Color("62644e")
const C_WALL_R := Color("4c4e3a")
const C_COL_L := Color("4a5a4e")
const C_COL_R := Color("36443a")
const C_MOSS_D := Color("3f5a2a")
const C_MOSS_M := Color("587537")
const C_MOSS_L := Color("7c9a48")
const C_TEAL := Color("3a9e9a")          # --echo accent: switches, gate, glows
const C_PLATE := Color("2f7e7c")
const C_PLATE_ON := Color("5fd6cf")
const C_EXIT := Color("2a6f6e")
const C_EXIT_ON := Color("4fe0da")
const C_PLAYER := Color("d98a52")        # Portal-orange player
const C_PLAYER_DARK := Color("b06a36")
const C_PLAYER_OUTLINE := Color("7c4a22")
const C_GHOST := Color("8a78bf")         # phase-ghost purple
const C_PHASE_RING := Color("6fb6c8")
const C_BG_IN := Color("5c6450")
const C_BG_MID := Color("3c4234")
const C_BG_OUT := Color("262a20")
const C_VIGNETTE := Color(0.063, 0.078, 0.047, 0.62)
const C_PIT_TEETH := Color("7d7a6f")

const SPR := {
	"floor_a": {"path": "res://assets/sprites/floor_a.png", "anchor": Vector2(48, 32)},
	"floor_b": {"path": "res://assets/sprites/floor_b.png", "anchor": Vector2(48, 32)},
	"wall":    {"path": "res://assets/sprites/wall.png",    "anchor": Vector2(48, 60)},
	"plate":   {"path": "res://assets/sprites/plate.png",   "anchor": Vector2(36, 22)},
	"exit":    {"path": "res://assets/sprites/exit.png",    "anchor": Vector2(44, 30)},
	"hazard":  {"path": "res://assets/sprites/hazard.png",  "anchor": Vector2(48, 32)},
}
var tex := {}
var bg_tex: GradientTexture2D

enum Mode { PHYSICAL, PHASE }

# ---- deterministic noise (ported from iso-tilemap.jsx) ----
func _hash(n: float) -> float:
	var s := sin(n * 127.1 + 311.7) * 43758.5453
	return s - floor(s)

func _blob(cx: float, cy: float, rx: float, ry: float, n: int, sd: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := (float(i) / n) * TAU
		var rr := 0.55 + 0.45 * _hash(sd + i * 1.7)
		pts.append(Vector2(cx + cos(a) * rx * rr, cy + sin(a) * ry * rr))
	return pts

# ---- Levels ( # wall, . floor, P start, E exit, ^ hazard, 1-9 plates ).
#      Optional: heights (digit grid), vines ([Vector2i] wall cells with hanging vines). ----
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
		"vines": [Vector2i(2, 0), Vector2i(6, 0), Vector2i(0, 3)],
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
		"vines": [Vector2i(3, 0), Vector2i(7, 0), Vector2i(0, 4)],
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
		"vines": [Vector2i(1, 0), Vector2i(7, 0)],
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
		"vines": [Vector2i(1, 0), Vector2i(5, 0)],
	},
]

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII"]
func _roman(n: int) -> String:
	return ROMAN[n] if n >= 0 and n < ROMAN.size() else str(n + 1)

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
var vines: Array = []
var plates: Array[Vector2i] = []
var exit_cell := Vector2i.ZERO
var start_cell := Vector2i.ZERO
var board_offset := Vector2.ZERO

# ---- Run state ----
var mode: int = Mode.PHYSICAL
var tick := 0
var player_cell := Vector2i.ZERO
var current_path: Array = []
var echoes: Array = []
var pressed_plates := {}
var exit_open := false
var won := false
var busy := false
var message := ""

# ---- Pawn draw animation (painter-sorted; no separate token nodes) ----
var player_pos_from := Vector2.ZERO
var player_pos_to := Vector2.ZERO
var echo_pos_from: Array = []
var echo_pos_to: Array = []
var anim_t := 1.0

# ---- HUD nodes ----
var title_box: Control
var title_card: Label
var subtitle: Label
var prompt: Label
var status: Label
var help: Label
var banner: Label
var show_help := false
var title_tween: Tween

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()
	_build_bg()
	_build_vignette()
	_build_hud()
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

func _build_bg() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.56, 1.0])
	g.colors = PackedColorArray([C_BG_IN, C_BG_MID, C_BG_OUT])
	bg_tex = GradientTexture2D.new()
	bg_tex.gradient = g
	bg_tex.fill = GradientTexture2D.FILL_RADIAL
	bg_tex.fill_from = Vector2(0.5, 0.42)
	bg_tex.fill_to = Vector2(1.08, 1.0)
	bg_tex.width = 256
	bg_tex.height = 256

func _build_vignette() -> void:
	var vg := Gradient.new()
	var clear := Color(C_VIGNETTE.r, C_VIGNETTE.g, C_VIGNETTE.b, 0.0)
	vg.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	vg.colors = PackedColorArray([clear, clear, C_VIGNETTE])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.46)
	vt.fill_to = Vector2(1.15, 1.0)
	vt.width = 256
	vt.height = 256
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var rect := TextureRect.new()
	rect.texture = vt
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)

func _mklabel(parent: Node, fs: int, col: Color, osize: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", osize)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.horizontal_alignment = align as HorizontalAlignment
	parent.add_child(l)
	return l

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)
	# Title card (fades on level load)
	title_box = Control.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(title_box)
	title_card = _mklabel(title_box, 46, Color("e8e2d0"), 8, HORIZONTAL_ALIGNMENT_CENTER)
	title_card.position = Vector2(0, 96)
	title_card.size = Vector2(1280, 60)
	subtitle = _mklabel(title_box, 17, Color("9fb0a0"), 5, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.position = Vector2(0, 158)
	subtitle.size = Vector2(1280, 30)
	# Contextual prompt (bottom center)
	prompt = _mklabel(cl, 16, Color("c6cfbe"), 5, HORIZONTAL_ALIGNMENT_CENTER)
	prompt.position = Vector2(0, 660)
	prompt.size = Vector2(1280, 26)
	prompt.modulate.a = 0.82
	# Tiny status (top-left)
	status = _mklabel(cl, 14, Color("a9b6a0"), 4, HORIZONTAL_ALIGNMENT_LEFT)
	status.position = Vector2(22, 18)
	status.size = Vector2(420, 24)
	status.modulate.a = 0.8
	# Help overlay (toggle H)
	help = _mklabel(cl, 16, Color("d7e2d0"), 5, HORIZONTAL_ALIGNMENT_LEFT)
	help.position = Vector2(22, 54)
	help.size = Vector2(640, 220)
	help.visible = false
	help.text = "CONTROLS\nMove: Arrows / WASD     Wait: Space\nF: Phase / Commit ghost     Q: cancel phase\nE: Swap with nearest ghost\nT: reset level     N: next (after solving)\nEsc: title     H: hide this help"
	# Win banner
	banner = _mklabel(cl, 36, Color("ffe9a8"), 8, HORIZONTAL_ALIGNMENT_CENTER)
	banner.position = Vector2(0, 300)
	banner.size = Vector2(1280, 60)
	banner.visible = false

func _show_title() -> void:
	title_card.text = "%s · %s" % [_roman(level_index), level_name]
	subtitle.text = level_hint
	title_box.modulate.a = 1.0
	if title_tween and title_tween.is_valid():
		title_tween.kill()
	title_tween = create_tween()
	title_tween.tween_interval(2.6)
	title_tween.tween_property(title_box, "modulate:a", 0.0, 1.4)

# ---- Level loading ----
func load_level(idx: int) -> void:
	level_index = idx
	var data: Dictionary = levels[idx]
	level_name = data["name"]
	level_hint = data.get("hint", "")
	var rows: Array = data["rows"]
	var hrows: Array = data.get("heights", [])
	vines = data.get("vines", [])
	walls.clear(); floors.clear(); hazards.clear(); heights.clear(); plates.clear()
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
	echoes.clear()
	_restart_attempt()
	_show_title()

# ---- Pawn draw positions ----
func _player_draw() -> Vector2:
	return player_pos_from.lerp(player_pos_to, anim_t)

func _echo_draw(i: int) -> Vector2:
	return echo_pos_from[i].lerp(echo_pos_to[i], anim_t)

func _snap_positions() -> void:
	var pp := _surface(player_cell)
	player_pos_from = pp
	player_pos_to = pp
	echo_pos_from.clear(); echo_pos_to.clear()
	for i in range(echoes.size()):
		var ep := _surface(_echo_pos(echoes[i], tick))
		echo_pos_from.append(ep)
		echo_pos_to.append(ep)
	anim_t = 1.0
	queue_redraw()

func _set_anim(t: float) -> void:
	anim_t = t
	queue_redraw()

# ---- Attempt / phase control ----
func _restart_attempt() -> void:
	mode = Mode.PHYSICAL
	tick = 0
	player_cell = start_cell
	current_path = [start_cell]
	won = false; banner.visible = false
	_snap_positions()
	_update_state()
	_update_hud()

func _begin_phase() -> void:
	mode = Mode.PHASE
	tick = 0
	player_cell = start_cell
	current_path = [start_cell]
	message = ""
	_snap_positions()
	_update_state()
	_update_hud()

func _commit_phase() -> void:
	if current_path.size() > 1:
		echoes.append({"path": current_path.duplicate()})
		message = "Ghost %d set. Phase again or solve physically." % echoes.size()
	_restart_attempt()

func _cancel_phase() -> void:
	message = "Phase cancelled."
	_restart_attempt()

func _full_reset() -> void:
	load_level(level_index)

func _next_level() -> void:
	load_level((level_index + 1) % levels.size())

# ---- Input ----
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	match k:
		KEY_T, KEY_BACKSPACE: _full_reset(); return
		KEY_H:
			show_help = not show_help
			help.visible = show_help
			return
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
	player_pos_from = _player_draw()
	for i in range(echoes.size()):
		echo_pos_from[i] = _echo_draw(i)
	player_cell = new_cell
	tick += 1
	if record:
		current_path.append(new_cell)
	player_pos_to = _surface(player_cell)
	for i in range(echoes.size()):
		echo_pos_to[i] = _surface(_echo_pos(echoes[i], tick))
	anim_t = 0.0
	busy = true
	var tw := create_tween()
	tw.tween_method(_set_anim, 0.0, 1.0, move_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
			banner.text = "ALL CHAMBERS CLEARED!   N = restart"
		else:
			banner.text = "CHAMBER SOLVED!   N = next"
		banner.visible = true

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

# ---- Overgrowth dressing ----
func _draw_moss(cx: float, cy: float, r: float, sd: float, alpha := 1.0) -> void:
	draw_colored_polygon(_blob(cx, cy, r, r * 0.5, 9, sd), Color(C_MOSS_D.r, C_MOSS_D.g, C_MOSS_D.b, alpha))
	draw_colored_polygon(_blob(cx, cy - 1, r * 0.78, r * 0.4, 8, sd + 5), Color(C_MOSS_M.r, C_MOSS_M.g, C_MOSS_M.b, alpha))
	draw_colored_polygon(_blob(cx - r * 0.2, cy - 2, r * 0.46, r * 0.24, 7, sd + 11), Color(C_MOSS_L.r, C_MOSS_L.g, C_MOSS_L.b, alpha))

func _draw_vine(x: float, y: float, length: float, sd: float) -> void:
	var segs := 6
	var step := length / segs
	var pts := PackedVector2Array()
	pts.append(Vector2(x, y))
	for i in range(1, segs + 1):
		var sway := sin(i * 1.3 + sd) * 7.0
		pts.append(Vector2(x + sway, y + step * i))
	draw_polyline(pts, Color(C_MOSS_D.r, C_MOSS_D.g, C_MOSS_D.b, 0.95), 2.4)
	for i in range(1, segs + 1):
		var sway2 := sin(i * 1.3 + sd) * 7.0
		var lp := Vector2(x + sway2 + (5 if i % 2 else -5), y + step * i)
		draw_circle(lp, 3.0, C_MOSS_M if i % 2 else C_MOSS_L)

# ---- Vector pawns (painter-sorted, ported from design Figure) ----
func _draw_stadium(cx: float, top: float, w: float, h: float, col: Color) -> void:
	var hw := w * 0.5
	if h > w:
		draw_rect(Rect2(cx - hw, top + hw, w, h - 2.0 * hw), col)
		draw_circle(Vector2(cx, top + hw), hw, col)
		draw_circle(Vector2(cx, top + h - hw), hw, col)
	else:
		draw_circle(Vector2(cx, top + h * 0.5), hw, col)

func _draw_pawn(pos: Vector2, kind: int) -> void:
	var ghost := kind == 2
	var phase := kind == 1
	var body := C_GHOST if ghost else C_PLAYER
	var outline := C_GHOST.darkened(0.4) if ghost else C_PLAYER_OUTLINE
	var a := echo_alpha if ghost else (phase_alpha if phase else 1.0)
	var cx := pos.x
	# ground shadow
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 16.0, Color(0, 0, 0, (0.12 if ghost else 0.26) * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var bw := 22.0
	var bh := 40.0
	var top := pos.y - bh - 3.0
	var headc := Vector2(cx, top - 5.0)
	# outline silhouette
	_draw_stadium(cx, top - 2.0, bw + 4.0, bh + 4.0, Color(outline.r, outline.g, outline.b, a))
	draw_circle(headc, 11.0, Color(outline.r, outline.g, outline.b, a))
	# fill
	_draw_stadium(cx, top, bw, bh, Color(body.r, body.g, body.b, a))
	draw_circle(headc, 9.0, Color(body.r, body.g, body.b, a))
	# left highlight (physical player reads solid)
	if not ghost:
		var hl := C_PLAYER.lightened(0.28)
		draw_circle(Vector2(cx - 4.0, headc.y - 2.0), 3.4, Color(hl.r, hl.g, hl.b, a))
	# rings
	if ghost:
		draw_arc(Vector2(cx, top + bh * 0.4), 25.0, 0.0, TAU, 30, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.5 * a), 1.6)
	elif phase:
		draw_arc(Vector2(cx, top + bh * 0.4), 25.0, 0.0, TAU, 30, Color(C_PHASE_RING.r, C_PHASE_RING.g, C_PHASE_RING.b, 0.65), 1.6)

# ---- Rendering: one back-to-front painter pass (tiles, walls, pawns interleaved) ----
func _draw() -> void:
	draw_texture_rect(bg_tex, Rect2(Vector2.ZERO, get_viewport_rect().size), false)
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
		_draw_pawns_at(s)
	_draw_paths()

func _draw_pawns_at(s: int) -> void:
	# ghosts first (so the live player reads on top when co-located)
	for i in range(echoes.size()):
		var gc := _echo_pos(echoes[i], tick)
		if gc.x + gc.y == s:
			_draw_pawn(_echo_draw(i), 2)
	if player_cell.x + player_cell.y == s:
		_draw_pawn(_player_draw(), 1 if mode == Mode.PHASE else 0)

func _draw_floor(cell: Vector2i) -> void:
	var c := _surface(cell)
	var h := _height(cell)
	if h > 0:
		_draw_column(c, h * level_step)
	if hazards.has(cell):
		if not _blit("hazard", c):
			draw_colored_polygon(_diamond(c, tile_w, tile_h), Color("1d1b17"))
			for i in range(-1, 2):
				var tx := c.x + i * 18.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(tx - 7, c.y + 4), Vector2(tx + 7, c.y + 4), Vector2(tx, c.y - 12)]), C_PIT_TEETH)
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
		var ga := 0.6 if on else 0.3
		draw_colored_polygon(_diamond(c, tile_w * 1.0, tile_h * 1.0), Color(glow.r, glow.g, glow.b, ga * 0.4))
		draw_colored_polygon(_diamond(c, tile_w * 0.5, tile_h * 0.5), Color(glow.r, glow.g, glow.b, ga))
	if cell == exit_cell:
		if not _blit("exit", c):
			draw_colored_polygon(_diamond(c, tile_w * 0.78, tile_h * 0.78), C_EXIT.darkened(0.35))
			draw_colored_polygon(_diamond(c, tile_w * 0.52, tile_h * 0.52), C_EXIT)
		var ecol := C_EXIT_ON if exit_open else C_EXIT
		var ea := 0.7 if exit_open else 0.32
		draw_colored_polygon(_diamond(c, tile_w * 0.4, tile_h * 0.4), Color(ecol.r, ecol.g, ecol.b, ea))
		if exit_open:
			draw_colored_polygon(_diamond(c, tile_w * 0.2, tile_h * 0.2), Color(1, 1, 1, 0.5))
			var bw := tile_w * 0.16
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-bw, 0), c + Vector2(bw, 0),
				c + Vector2(bw * 0.55, -84.0), c + Vector2(-bw * 0.55, -84.0)]),
				Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.16))

func _draw_wall(cell: Vector2i) -> void:
	var has_sprite := _blit("wall", _ground(cell))
	if not has_sprite:
		var base := _ground(cell)
		var top := base - Vector2(0, wall_height)
		var b := _diamond(base, tile_w, tile_h)
		var t := _diamond(top, tile_w, tile_h)
		draw_colored_polygon(PackedVector2Array([t[3], t[2], b[2], b[3]]), C_WALL_L)
		draw_colored_polygon(PackedVector2Array([t[2], t[1], b[1], b[2]]), C_WALL_R)
		draw_colored_polygon(t, C_WALL_TOP)
		var ol := t.duplicate(); ol.append(t[0])
		draw_polyline(ol, C_WALL_TOP.darkened(0.4), 2.0)
		# procedural moss creeping over the top edge
		var sd := cell.x * 7.1 + cell.y * 3.3
		if _hash(sd) > 0.35:
			_draw_moss(top.x - 6, top.y + 2, 13.0, sd, 0.95)
	# hanging vine (data-driven, on top of sprite or shapes)
	if vines.has(cell):
		var base2 := _ground(cell)
		var sx := base2.x - tile_w * 0.22
		var sy := base2.y - wall_height + 8.0
		_draw_vine(sx, sy, wall_height + 8.0, cell.x * 2.7 + cell.y * 1.9)

# ---- Path traces (guides) ----
func _draw_trace(path: Array, col: Color, w: float) -> void:
	if path.size() < 1:
		return
	var pts := PackedVector2Array()
	for cell in path:
		pts.append(_surface(cell))
	if pts.size() >= 2:
		draw_polyline(pts, col, w)
	for p in pts:
		draw_circle(p, w * 1.2, col)

func _draw_paths() -> void:
	for e in echoes:
		_draw_trace(e["path"], Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.26), 2.0)
	if mode == Mode.PHASE and current_path.size() > 1:
		_draw_trace(current_path, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.9), 3.0)

# ---- Minimal HUD ----
func _update_hud() -> void:
	if plates.size() > 0:
		var pc := 0
		for p in plates:
			if pressed_plates.get(p, false):
				pc += 1
		status.text = "switches %d/%d    ghosts %d" % [pc, plates.size(), echoes.size()]
		status.visible = true
	else:
		status.text = "ghosts %d" % echoes.size()
		status.visible = echoes.size() > 0
	var base := ""
	if mode == Mode.PHASE:
		base = "PHASE  —  move through walls  ·  F commit  ·  Q cancel"
	else:
		var bits := ["F phase"]
		if echoes.size() > 0:
			bits.append("E swap")
		bits.append("H help")
		base = "  ·  ".join(bits)
	if message != "":
		base = message + "       " + base
	prompt.text = base
