extends Node2D
## A pawn token. Draws a sprite if one is provided, else a procedural pawn.
## Position is driven (tweened) by Main in screen space; the token's "feet" sit
## on the tile center.

var body_color: Color = Color.WHITE
var alpha: float = 1.0
var label_text: String = ""
var texture: Texture2D = null
var anchor: Vector2 = Vector2(22, 56)   # feet point within the sprite
var token_h: float = 36.0
var token_r: float = 13.0

func setup(c: Color, a: float, t: String, tex: Texture2D = null) -> void:
	body_color = c
	alpha = a
	label_text = t
	texture = tex
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func _draw() -> void:
	var col := Color(body_color.r, body_color.g, body_color.b, alpha)

	# Ground shadow (squashed ellipse).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, (token_r if texture == null else 14.0) * 1.15, Color(0, 0, 0, 0.28 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if texture != null:
		# Player draws at full color (modulate white); echoes tint toward ghost-blue.
		draw_texture(texture, -anchor, col)
	else:
		var dark := col.darkened(0.4)
		var light := col.lightened(0.4)
		var head_pos := Vector2(0, -token_h)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-token_r * 0.55, -2), Vector2(token_r * 0.55, -2),
			Vector2(token_r * 0.45, -token_h + token_r), Vector2(-token_r * 0.45, -token_h + token_r),
		]), dark)
		draw_circle(head_pos, token_r, col)
		draw_circle(head_pos + Vector2(-token_r * 0.3, -token_r * 0.3), token_r * 0.38, light)

	if label_text != "":
		var f := ThemeDB.fallback_font
		var fs := 14
		var hp := Vector2(0, -42) if texture != null else Vector2(0, -token_h)
		var w := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, hp + Vector2(-w * 0.5, fs * 0.4), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.1, 0.15, 0.9 * alpha))
