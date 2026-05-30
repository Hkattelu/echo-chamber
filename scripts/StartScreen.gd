extends Control
## Simple title screen for Echo Chamber. Press any key / click to start.
## Decorative isometric backdrop drawn in code so it needs no assets.

const C_BG := Color("11131c")
const C_FLOOR := Color("3a4a63")
const C_FLOOR_EDGE := Color("2a3650")
const C_PLAYER := Color("ffd23f")
const C_ECHO := Color("46c9ff")

const TILE_W := 96.0
const TILE_H := 48.0

var _t := 0.0
var _prompt: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_add_label("ECHO CHAMBER", Vector2(0, 150), 1280, 72, Color("e7f0e0"), C_ECHO, 10)
	_add_label("an isometric puzzle of echoes", Vector2(0, 248), 1280, 24, Color("9fb3a4"), Color.BLACK, 4)

	_prompt = _add_label("PRESS  ENTER  TO  BEGIN", Vector2(0, 470), 1280, 30, C_PLAYER, Color.BLACK, 6)

	_add_label(
		"Arrows/WASD: move   F: phase/commit ghost   E: swap   Space: wait   T: reset   Esc: title",
		Vector2(0, 632), 1280, 16, Color("7d8f82"), Color.BLACK, 3)

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
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		go = true
	elif event is InputEventMouseButton and event.pressed:
		go = true
	if go:
		get_tree().change_scene_to_file("res://main.tscn")

# --- decorative backdrop ---
func _iso(cell: Vector2, origin: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE_W * 0.5, (cell.x + cell.y) * TILE_H * 0.5) + origin

func _diamond(c: Vector2, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -h * 0.5), c + Vector2(w * 0.5, 0),
		c + Vector2(0, h * 0.5), c + Vector2(-w * 0.5, 0)])

func _pawn(pos: Vector2, col: Color, a: float) -> void:
	var c := Color(col.r, col.g, col.b, a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
	draw_circle(Vector2(pos.x, pos.y * 2.0), 15, Color(0, 0, 0, 0.25 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-7, -2), pos + Vector2(7, -2),
		pos + Vector2(6, -30), pos + Vector2(-6, -30)]), c.darkened(0.4))
	draw_circle(pos + Vector2(0, -42), 13, c)
	draw_circle(pos + Vector2(-4, -46), 5, c.lightened(0.4))

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), C_BG)

	# Faint full-screen iso lattice.
	var origin := Vector2(vp.x * 0.5, vp.y * 0.5 + 70)
	for sx in range(-6, 7):
		for sy in range(-5, 6):
			var c := _iso(Vector2(sx, sy), origin)
			var d := _diamond(c, TILE_W, TILE_H)
			var dist := Vector2(sx, sy).length()
			var a: float = clampf(0.16 - dist * 0.012, 0.0, 0.16)
			if a > 0.0:
				draw_colored_polygon(d, Color(C_FLOOR.r, C_FLOOR.g, C_FLOOR.b, a))

	# A solid little floating platform of tiles near the bottom-center.
	var plat := [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0),
		Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
	for cell in plat:
		var c := _iso(cell, origin)
		var d := _diamond(c, TILE_W, TILE_H)
		draw_colored_polygon(d, C_FLOOR)
		var ol := d.duplicate(); ol.append(d[0])
		draw_polyline(ol, C_FLOOR_EDGE, 2.0)

	# Pawns: one player flanked by two drifting echoes.
	var bob := sin(_t * 2.0) * 3.0
	_pawn(_iso(Vector2(0, 0), origin) + Vector2(0, -2), C_PLAYER, 1.0)
	_pawn(_iso(Vector2(-1, 1), origin) + Vector2(0, -2 + bob), C_ECHO, 0.55)
	_pawn(_iso(Vector2(1, 1), origin) + Vector2(0, -2 - bob), C_ECHO, 0.55)
