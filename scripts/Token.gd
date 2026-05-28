extends Node2D
## A pawn token drawn in code. Used for the live player and for echo clones.
## Set via setup(); position is driven (tweened) by Main in screen space.

var body_color: Color = Color.WHITE
var alpha: float = 1.0
var label_text: String = ""
var token_h: float = 36.0   # pawn height in px
var token_r: float = 13.0   # head radius in px

func setup(c: Color, a: float, t: String) -> void:
	body_color = c
	alpha = a
	label_text = t
	queue_redraw()

func _draw() -> void:
	var col := Color(body_color.r, body_color.g, body_color.b, alpha)
	var dark := col.darkened(0.4)
	var light := col.lightened(0.4)

	# Ground shadow (squashed ellipse) so the pawn reads as "on" the tile.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, token_r * 1.15, Color(0, 0, 0, 0.28 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Body (tapered stem from the ground up to the head).
	var head_pos := Vector2(0, -token_h)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-token_r * 0.55, -2),
		Vector2(token_r * 0.55, -2),
		Vector2(token_r * 0.45, -token_h + token_r),
		Vector2(-token_r * 0.45, -token_h + token_r),
	]), dark)

	# Head.
	draw_circle(head_pos, token_r, col)
	draw_circle(head_pos + Vector2(-token_r * 0.3, -token_r * 0.3), token_r * 0.38, light)

	# Optional label (echo number).
	if label_text != "":
		var f := ThemeDB.fallback_font
		var fs := 14
		var w := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, head_pos + Vector2(-w * 0.5, fs * 0.4), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85 * alpha))
