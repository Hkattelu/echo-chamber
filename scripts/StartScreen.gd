extends Control
## Title screen for Echo Chamber. Press any key / click to start.
## Worn overgrown-tower palette matching the in-game restyle.

const C_BG_IN := Color("4a5142")
const C_BG_MID := Color("343a2c")
const C_BG_OUT := Color("20251c")
const C_FLOOR := Color("5c6450")
const C_FLOOR_EDGE := Color("3c4234")
const C_PLAYER := Color("d98a52")
const C_GHOST := Color("8a78bf")
const C_TEAL := Color("4fe0da")

const TILE_W := 96.0
const TILE_H := 48.0

var _t := 0.0
var _prompt: Label
var bg_tex: GradientTexture2D

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([C_BG_IN, C_BG_MID, C_BG_OUT])
	bg_tex = GradientTexture2D.new()
	bg_tex.gradient = g
	bg_tex.fill = GradientTexture2D.FILL_RADIAL
	bg_tex.fill_from = Vector2(0.5, 0.42)
	bg_tex.fill_to = Vector2(1.05, 1.0)
	bg_tex.width = 256
	bg_tex.height = 256

	_add_label("THE  TOWER  REMEMBERS", Vector2(0, 116), 1280, 18, Color("9fb0a0"), Color.BLACK, 4)
	_add_label("ECHO CHAMBER", Vector2(0, 150), 1280, 74, Color("ece3d0"), C_TEAL, 10)
	_add_label("an overgrown tower of echoes", Vector2(0, 256), 1280, 24, Color("9fb3a4"), Color.BLACK, 4)
	_prompt = _add_label("PRESS  ENTER  TO  BEGIN", Vector2(0, 474), 1280, 30, C_PLAYER, Color.BLACK, 6)
	_add_label(
		"Arrows / WASD: move      Hold SPACE: record a ghost      R: reset      H: help      F11: fullscreen",
		Vector2(0, 636), 1280, 16, Color("7d8f82"), Color.BLACK, 3)

func _add_label(text: String, pos: Vector2, w: int, fs: int, col: Color, outline: Color, osize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(w, fs + 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", osize)
	l.add_theme_color_override("font_outline_color", outline)
	add_child(l)
	return l

func _process(delta: float) -> void:
	_t += delta
	if _prompt:
		_prompt.modulate.a = 0.45 + 0.55 * absf(sin(_t * 3.0))
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_F11:
			var m := DisplayServer.window_get_mode()
			if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			get_tree().change_scene_to_file("res://main.tscn")
	elif event is InputEventMouseButton and event.pressed:
		get_tree().change_scene_to_file("res://main.tscn")

func _iso(cell: Vector2, origin: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE_W * 0.5, (cell.x + cell.y) * TILE_H * 0.5) + origin

func _diamond(c: Vector2, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -h * 0.5), c + Vector2(w * 0.5, 0),
		c + Vector2(0, h * 0.5), c + Vector2(-w * 0.5, 0)])

func _pawn(pos: Vector2, col: Color, a: float) -> void:
	var c := Color(col.r, col.g, col.b, a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
	draw_circle(Vector2(pos.x, pos.y * 2.0), 15, Color(0, 0, 0, 0.22 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-7, -2), pos + Vector2(7, -2),
		pos + Vector2(6, -30), pos + Vector2(-6, -30)]), c.darkened(0.4))
	draw_circle(pos + Vector2(0, -42), 13, c)
	draw_circle(pos + Vector2(-4, -46), 5, c.lightened(0.4))

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_texture_rect(bg_tex, Rect2(Vector2.ZERO, vp), false)
	var origin := Vector2(vp.x * 0.5, vp.y * 0.5 + 70)
	for sx in range(-6, 7):
		for sy in range(-5, 6):
			var c := _iso(Vector2(sx, sy), origin)
			var d := _diamond(c, TILE_W, TILE_H)
			var dist := Vector2(sx, sy).length()
			var a: float = clampf(0.16 - dist * 0.012, 0.0, 0.16)
			if a > 0.0:
				draw_colored_polygon(d, Color(C_FLOOR.r, C_FLOOR.g, C_FLOOR.b, a))
	var plat := [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0),
		Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
	for cell in plat:
		var c := _iso(cell, origin)
		var d := _diamond(c, TILE_W, TILE_H)
		draw_colored_polygon(d, C_FLOOR)
		var ol := d.duplicate(); ol.append(d[0])
		draw_polyline(ol, C_FLOOR_EDGE, 2.0)
	var bob := sin(_t * 2.0) * 3.0
	_pawn(_iso(Vector2(0, 0), origin) + Vector2(0, -2), C_PLAYER, 1.0)
	_pawn(_iso(Vector2(-1, 1), origin) + Vector2(0, -2 + bob), C_GHOST, 0.6)
	_pawn(_iso(Vector2(1, 1), origin) + Vector2(0, -2 - bob), C_GHOST, 0.6)
