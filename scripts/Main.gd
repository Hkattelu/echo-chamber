extends Node2D
## ECHO CHAMBER — 2D isometric temporal-puzzle prototype.
## Worn overgrown-tower look; "motion record" mechanic.
##
## Turn-based, deterministic lockstep. Two-step "record then deploy" model:
##   1. HOLD SPACE to RECORD a gesture: while held you walk (through walls — you are phasing),
##      each step recorded as a relative shape. RELEASE to BANK that shape into a reusable
##      clipboard (gesture_deltas) and snap back — this does NOT spawn a ghost. Re-recording
##      replaces the clipboard.
##   2. Walk anywhere, then press E (deploy/echo) to STAMP a ghost at your CURRENT cell that
##      traces the recorded shape from there. Deploying does NOT consume the clipboard — stamp
##      the same shape from as many positions as you like.
## Ghosts replay in lockstep with your future moves and freeze on their last step (holding a
## switch). Stack ghosts to hold switches simultaneously; the exit opens when all switches are
## held — then walk onto it. When NOT recording you are solid: walls block, spike pits kill.

# ---- Tunable game-feel knobs ----
@export var tile_w: int = 112
@export var tile_h: int = 56
@export var wall_height: int = 46
@export var level_step: int = 28
@export var max_climb: int = 1
@export var move_time: float = 0.10
@export var echo_alpha: float = 0.62
@export var phase_alpha: float = 0.5

# ---- Palette (worn overgrown tower) ----
const C_FLOOR := Color("9ea08d")
const C_FLOOR_EDGE := Color("585a47")
const C_WALL_TOP := Color("8b8d78")
const C_WALL_L := Color("62644e")
const C_WALL_R := Color("4c4e3a")
const C_COL_L := Color("4a5a4e")
const C_COL_R := Color("36443a")
const C_MOSS_D := Color("46602f")
const C_MOSS_M := Color("5d7a3a")
const C_PLATE := Color("2f7e7c")
const C_PLATE_ON := Color("5fd6cf")
const C_EXIT := Color("2a6f6e")
const C_EXIT_ON := Color("4fe0da")
const C_PLAYER := Color("d98a52")
const C_PLAYER_DARK := Color("b06a36")
const C_PLAYER_OUTLINE := Color("7c4a22")
const C_GHOST := Color("8a78bf")
const C_PHASE_RING := Color("6fb6c8")
const C_BG_IN := Color("5c6450")
const C_BG_MID := Color("3c4234")
const C_BG_OUT := Color("262a20")
const C_VIGNETTE := Color(0.063, 0.078, 0.047, 0.62)
const C_PIT_TEETH := Color("8c8a7e")

const SPR := {
  # Base ground/wall are now PixelLab iso tiles too (mossy weathered stone, replacing the old
  # Aseprite green-blob tiles) -> same (32,47)/1.75 convention as the decor below.
  "floor_a": {"path": "res://assets/sprites/floor_a.png", "anchor": Vector2(32, 47), "scale": 1.75},
  "floor_b": {"path": "res://assets/sprites/floor_b.png", "anchor": Vector2(32, 47), "scale": 1.75},
  "wall":    {"path": "res://assets/sprites/wall.png",    "anchor": Vector2(32, 47), "scale": 1.75},
  "hazard":  {"path": "res://assets/sprites/hazard.png",  "anchor": Vector2(56, 38)},
  # PixelLab iso tiles (64x64). Footprint diamond centre is at source (32,47);
  # scaled x1.75 -> exact 112x56 tile footprint (matches floor/wall geometry).
  "door_closed":  {"path": "res://assets/sprites/door_closed.png",  "anchor": Vector2(32, 47), "scale": 1.75},
  "door_open":    {"path": "res://assets/sprites/door_open.png",    "anchor": Vector2(32, 47), "scale": 1.75},
  "crystal":      {"path": "res://assets/sprites/crystal.png",      "anchor": Vector2(32, 47), "scale": 1.75},
  "brazier":      {"path": "res://assets/sprites/brazier.png",      "anchor": Vector2(32, 47), "scale": 1.75},
  "wall_mossy":   {"path": "res://assets/sprites/wall_mossy.png",   "anchor": Vector2(32, 47), "scale": 1.75},
  "wall_cracked": {"path": "res://assets/sprites/wall_cracked.png", "anchor": Vector2(32, 47), "scale": 1.75},
  "rubble":       {"path": "res://assets/sprites/rubble.png",       "anchor": Vector2(32, 47), "scale": 1.75},
  "mushrooms":    {"path": "res://assets/sprites/mushrooms.png",    "anchor": Vector2(32, 47), "scale": 1.75},
  "plate":        {"path": "res://assets/sprites/plate.png",        "anchor": Vector2(32, 47), "scale": 1.75},
  "statue":       {"path": "res://assets/sprites/statue.png",       "anchor": Vector2(32, 47), "scale": 1.75},
  "obelisk":      {"path": "res://assets/sprites/obelisk.png",      "anchor": Vector2(32, 47), "scale": 1.75},
  "urn":          {"path": "res://assets/sprites/urn.png",          "anchor": Vector2(32, 47), "scale": 1.75},
  "ferns":        {"path": "res://assets/sprites/ferns.png",        "anchor": Vector2(32, 47), "scale": 1.75},
  # Character rotations (PixelLab 8-dir, 68px). Drawn in _draw_pawn at CHAR_SCALE with the
  # foot anchor CHAR_ANCHOR. pl_* = player (orange), gh_* = ghost echo (purple spectral).
  # Suffix is the iso facing: _se(+x) _sw(+y) _nw(-x) _ne(-y) _s(idle).
  "pl_s":  {"path": "res://assets/sprites/pl_s.png",  "anchor": Vector2(34, 58), "scale": 1.35},
  "pl_se": {"path": "res://assets/sprites/pl_se.png", "anchor": Vector2(34, 58), "scale": 1.35},
  "pl_sw": {"path": "res://assets/sprites/pl_sw.png", "anchor": Vector2(34, 58), "scale": 1.35},
  "pl_ne": {"path": "res://assets/sprites/pl_ne.png", "anchor": Vector2(34, 58), "scale": 1.35},
  "pl_nw": {"path": "res://assets/sprites/pl_nw.png", "anchor": Vector2(34, 58), "scale": 1.35},
  "gh_s":  {"path": "res://assets/sprites/gh_s.png",  "anchor": Vector2(34, 58), "scale": 1.35},
  "gh_se": {"path": "res://assets/sprites/gh_se.png", "anchor": Vector2(34, 58), "scale": 1.35},
  "gh_sw": {"path": "res://assets/sprites/gh_sw.png", "anchor": Vector2(34, 58), "scale": 1.35},
  "gh_ne": {"path": "res://assets/sprites/gh_ne.png", "anchor": Vector2(34, 58), "scale": 1.35},
  "gh_nw": {"path": "res://assets/sprites/gh_nw.png", "anchor": Vector2(34, 58), "scale": 1.35},
}
const CHAR_ANCHOR := Vector2(34, 58)   # foot point in the 68px character canvas
const CHAR_SCALE := 1.35
var tex := {}
var bg_tex: GradientTexture2D

enum Mode { PLAY, RECORD }

func _hash(n: float) -> float:
  var s := sin(n * 127.1 + 311.7) * 43758.5453
  return s - floor(s)

# ---- Levels ( # wall, . floor, P start, E exit, ^ spike pit, 1-9 switches ).
#      Optional: vines ([Vector2i] wall cells with a hanging vine). ----
var levels := [
  {
    "name": "Ghost Walk",
    "hint": "Hold SPACE and walk through the wall onto the switch, release to leave a ghost, then walk to the exit.",
    "rows": [
      "#########",
      "#...P...#",
      "#.......#",
      "#..###..#",
      "#..#1#..#",
      "#..###..#",
      "#...E...#",
      "#########"],
    "vines": [Vector2i(2, 0), Vector2i(6, 0)],
    "decor": [
      [Vector2i(4, 3), "crystal"],
      [Vector2i(3, 3), "wall_mossy"], [Vector2i(5, 3), "wall_cracked"],
      [Vector2i(3, 5), "wall_cracked"], [Vector2i(5, 5), "wall_mossy"],
      [Vector2i(1, 6), "brazier"], [Vector2i(7, 6), "brazier"],
      [Vector2i(2, 2), "ferns"], [Vector2i(6, 2), "rubble"], [Vector2i(6, 5), "urn"],
    ],
  },
  {
    "name": "Spike Gauntlet",
    "hint": "Spikes kill you (not your ghost). Leave a ghost on the switch, then pick the safe gap across the pit.",
    "rows": [
      "#########",
      "#..P..1.#",
      "#.......#",
      "#^^^^^.^#",
      "#.......#",
      "#...E...#",
      "#########"],
    "vines": [Vector2i(1, 0), Vector2i(7, 0)],
    "decor": [
      [Vector2i(8, 1), "crystal"], [Vector2i(0, 1), "statue"],
      [Vector2i(0, 3), "wall_mossy"], [Vector2i(8, 3), "wall_cracked"],
      [Vector2i(0, 5), "brazier"], [Vector2i(8, 5), "brazier"],
      [Vector2i(1, 4), "mushrooms"], [Vector2i(7, 4), "urn"],
    ],
  },
  {
    "name": "Dual Lock",
    "hint": "Two sealed switches. Record one ghost onto each, then walk down to the exit.",
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
    "vines": [Vector2i(3, 0), Vector2i(7, 0)],
    "decor": [
      [Vector2i(3, 3), "crystal"], [Vector2i(7, 3), "crystal"],
      [Vector2i(0, 1), "obelisk"], [Vector2i(10, 1), "statue"],
      [Vector2i(2, 3), "wall_mossy"], [Vector2i(4, 3), "wall_cracked"],
      [Vector2i(6, 3), "wall_cracked"], [Vector2i(8, 3), "wall_mossy"],
      [Vector2i(0, 7), "brazier"], [Vector2i(10, 7), "brazier"],
      [Vector2i(1, 2), "mushrooms"], [Vector2i(9, 6), "rubble"],
    ],
  },
  {
    "name": "Triad",
    "hint": "Three sealed switches need three ghosts. Phase one onto each, then take the exit.",
    "rows": [
      "###########",
      "#....P....#",
      "#.........#",
      "###.###.###",
      "#1#.#2#.#3#",
      "###.###.###",
      "#.........#",
      "#....E....#",
      "###########"],
    "vines": [Vector2i(0, 4), Vector2i(10, 4)],
    "decor": [
      [Vector2i(1, 3), "crystal"], [Vector2i(5, 3), "crystal"], [Vector2i(9, 3), "crystal"],
      [Vector2i(0, 3), "wall_mossy"], [Vector2i(2, 3), "wall_cracked"],
      [Vector2i(4, 3), "wall_cracked"], [Vector2i(6, 3), "wall_mossy"],
      [Vector2i(8, 3), "wall_mossy"], [Vector2i(10, 3), "wall_cracked"],
      [Vector2i(0, 1), "statue"], [Vector2i(10, 1), "obelisk"],
      [Vector2i(0, 7), "brazier"], [Vector2i(10, 7), "brazier"],
      [Vector2i(3, 6), "ferns"], [Vector2i(7, 6), "rubble"],
    ],
  },
  {
    "name": "Sentinel",
    "hint": "One switch, one exit — you can't stand on both. Record a short walk, deploy a ghost onto the switch, then take the exit.",
    "decor": [[Vector2i(6, 5), "brazier"], [Vector2i(5, 6), "brazier"], [Vector2i(0, 3), "crystal"], [Vector2i(1, 5), "ferns"], [Vector2i(5, 1), "rubble"]],
    "rows": [
      "#######",
      "#P....#",
      "#.....#",
      "#..1..#",
      "#.....#",
      "#....E#",
      "#######"],
  },
  {
    "name": "Phase Wall",
    "hint": "Hold SPACE to walk THROUGH the wall while recording. Deploy above the sealed switch so the ghost drops in.",
    "decor": [[Vector2i(6, 6), "brazier"], [Vector2i(5, 7), "brazier"], [Vector2i(3, 3), "crystal"], [Vector2i(2, 3), "wall_mossy"], [Vector2i(4, 3), "wall_cracked"], [Vector2i(1, 6), "ferns"]],
    "rows": [
      "#######",
      "#P....#",
      "#.....#",
      "#.###.#",
      "#.#1#.#",
      "#.###.#",
      "#....E#",
      "#######"],
  },
  {
    "name": "Hazard Hold",
    "hint": "Spikes kill you, not your ghost. Park a ghost on the switch, then thread the safe gap to the exit.",
    "decor": [[Vector2i(3, 6), "brazier"], [Vector2i(5, 6), "brazier"], [Vector2i(8, 1), "crystal"], [Vector2i(0, 1), "obelisk"], [Vector2i(1, 4), "ferns"], [Vector2i(7, 4), "urn"]],
    "rows": [
      "#########",
      "#P....1.#",
      "#.......#",
      "#^^^.^^^#",
      "#.......#",
      "#...E...#",
      "#########"],
    "vines": [Vector2i(0, 0), Vector2i(8, 0)],
  },
  {
    "name": "Twin Pillars",
    "hint": "Two switches, one gesture. Record once, then deploy the same shape from under each pillar.",
    "decor": [[Vector2i(3, 7), "brazier"], [Vector2i(5, 7), "brazier"], [Vector2i(0, 2), "crystal"], [Vector2i(8, 2), "crystal"], [Vector2i(1, 5), "ferns"], [Vector2i(7, 5), "rubble"]],
    "rows": [
      "#########",
      "#.......#",
      "#.1...2.#",
      "#.......#",
      "#...P...#",
      "#.......#",
      "#...E...#",
      "#########"],
  },
  {
    "name": "Inner Sanctum",
    "hint": "The switch is walled in. Record a long reach down, deploy from above, and let the ghost phase inside.",
    "decor": [[Vector2i(5, 2), "crystal"], [Vector2i(2, 2), "brazier"], [Vector2i(8, 2), "brazier"], [Vector2i(2, 6), "wall_mossy"], [Vector2i(8, 6), "wall_cracked"], [Vector2i(9, 1), "ferns"], [Vector2i(9, 7), "rubble"]],
    "rows": [
      "###########",
      "#P........#",
      "#.#######.#",
      "#.#.....#.#",
      "#.#..1..#.#",
      "#.#.....#.#",
      "#.#######.#",
      "#E........#",
      "###########"],
  },
  {
    "name": "Crossroads",
    "hint": "Switches sit across the pit from the exit. Cross the gap to plant both ghosts, then cross back.",
    "decor": [[Vector2i(3, 7), "brazier"], [Vector2i(5, 7), "brazier"], [Vector2i(0, 1), "crystal"], [Vector2i(8, 1), "crystal"], [Vector2i(1, 5), "ferns"], [Vector2i(7, 5), "rubble"]],
    "rows": [
      "#########",
      "#1.....2#",
      "#.......#",
      "#^^^.^^^#",
      "#.......#",
      "#...P...#",
      "#...E...#",
      "#########"],
    "vines": [Vector2i(0, 0), Vector2i(8, 0)],
  },
  {
    "name": "The Moat",
    "hint": "A ring of spikes guards the switch. Your ghost is immune — deploy so it walks across the lava.",
    "decor": [[Vector2i(8, 1), "brazier"], [Vector2i(7, 0), "brazier"], [Vector2i(0, 1), "obelisk"], [Vector2i(0, 8), "statue"], [Vector2i(1, 8), "ferns"], [Vector2i(7, 8), "rubble"]],
    "rows": [
      "#########",
      "#P.....E#",
      "#.......#",
      "#.^^^^^.#",
      "#.^...^.#",
      "#.^.1.^.#",
      "#.^...^.#",
      "#.^^^^^.#",
      "#.......#",
      "#########"],
  },
  {
    "name": "The Crossing",
    "hint": "You can't cross the spikes — but your echo can. Record a walk over them onto the switch, deploy on the safe edge, then take the long way around to the exit.",
    "decor": [[Vector2i(7, 0), "brazier"], [Vector2i(8, 1), "brazier"], [Vector2i(0, 4), "obelisk"], [Vector2i(0, 7), "statue"], [Vector2i(8, 7), "crystal"], [Vector2i(3, 2), "ferns"], [Vector2i(3, 3), "rubble"]],
    "rows": [
      "#########",
      "#......E#",
      "#.......#",
      "#.......#",
      "#P......#",
      "#^^^^^^^#",
      "#^^^^^^^#",
      "#...1...#",
      "#########"],
  },
  {
    "name": "Triptych",
    "hint": "Three switches in a row. One recorded step, deployed under each — then walk down to the exit.",
    "decor": [[Vector2i(4, 7), "brazier"], [Vector2i(6, 7), "brazier"], [Vector2i(0, 2), "crystal"], [Vector2i(10, 2), "crystal"], [Vector2i(0, 1), "statue"], [Vector2i(10, 1), "obelisk"], [Vector2i(1, 5), "ferns"], [Vector2i(9, 5), "rubble"]],
    "rows": [
      "###########",
      "#.........#",
      "#.1..2..3.#",
      "#.........#",
      "#....P....#",
      "#.........#",
      "#....E....#",
      "###########"],
  },
  {
    "name": "The Vault",
    "hint": "Three switches above the pit, the exit below. Cross up, stamp all three, then cross back down.",
    "decor": [[Vector2i(4, 10), "brazier"], [Vector2i(6, 10), "brazier"], [Vector2i(0, 1), "crystal"], [Vector2i(10, 1), "crystal"], [Vector2i(0, 3), "statue"], [Vector2i(10, 3), "obelisk"], [Vector2i(1, 8), "ferns"], [Vector2i(9, 8), "rubble"]],
    "rows": [
      "###########",
      "#.1.....3.#",
      "#.........#",
      "#....2....#",
      "#.........#",
      "#^^^^.^^^^#",
      "#.........#",
      "#....P....#",
      "#.........#",
      "#....E....#",
      "###########"],
    "vines": [Vector2i(0, 5), Vector2i(10, 5)],
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
var decor := {}   # cell (Vector2i) -> sprite name. Cosmetic props on wall/floor cells; no gameplay effect.
var exit_cell := Vector2i.ZERO
var start_cell := Vector2i.ZERO
var board_offset := Vector2.ZERO

# ---- Run state ----
var mode: int = Mode.PLAY
var tick := 0
var player_cell := Vector2i.ZERO
var player_face := Vector2i.ZERO  # last move delta -> character facing (ZERO = idle/front)
var rec_anchor := Vector2i.ZERO   # cell where the player pressed SPACE to start recording
var current_path: Array = []
var gesture_deltas: Array = []    # CLIPBOARD: last recorded gesture as relative deltas (deltas[0]==(0,0)).
                                  # Empty = nothing recorded. Filled on release SPACE, stamped by _deploy().
                                  # Persists across death/reset; cleared only on load_level (a fresh level).
var echoes: Array = []
var pressed_plates := {}
var exit_open := false
var won := false
var busy := false
var message := ""

# ---- Pawn draw animation ----
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
  title_box = Control.new()
  title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
  title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
  cl.add_child(title_box)
  title_card = _mklabel(title_box, 50, Color("e8e2d0"), 8, HORIZONTAL_ALIGNMENT_CENTER)
  title_card.position = Vector2(0, 92); title_card.size = Vector2(1280, 64)
  subtitle = _mklabel(title_box, 18, Color("9fb0a0"), 5, HORIZONTAL_ALIGNMENT_CENTER)
  subtitle.position = Vector2(160, 160); subtitle.size = Vector2(960, 30)
  subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  prompt = _mklabel(cl, 17, Color("c6cfbe"), 5, HORIZONTAL_ALIGNMENT_CENTER)
  prompt.position = Vector2(0, 662); prompt.size = Vector2(1280, 26)
  prompt.modulate.a = 0.85
  status = _mklabel(cl, 15, Color("a9b6a0"), 4, HORIZONTAL_ALIGNMENT_LEFT)
  status.position = Vector2(24, 18); status.size = Vector2(420, 24)
  status.modulate.a = 0.8
  help = _mklabel(cl, 16, Color("d7e2d0"), 5, HORIZONTAL_ALIGNMENT_LEFT)
  help.position = Vector2(24, 52); help.size = Vector2(720, 200)
  help.visible = false
  help.text = "CONTROLS\nMove: Arrows / WASD\nHold SPACE: record a gesture (walk through walls) — release to bank it as a reusable shape\nE: deploy — stamp a ghost at your position that traces the banked gesture (stamp from anywhere, as often as you like)\nRe-record (hold SPACE again) to replace the banked gesture.\nR / T: reset level    N: next (after solving)\nF11: fullscreen    Esc: title    H: hide help"
  banner = _mklabel(cl, 38, Color("ffe9a8"), 8, HORIZONTAL_ALIGNMENT_CENTER)
  banner.position = Vector2(0, 300); banner.size = Vector2(1280, 60)
  banner.visible = false

func _show_title() -> void:
  title_card.text = "%s · %s" % [_roman(level_index), level_name]
  subtitle.text = level_hint
  title_box.modulate.a = 1.0
  if title_tween and title_tween.is_valid():
    title_tween.kill()
  title_tween = create_tween()
  title_tween.tween_interval(3.0)
  title_tween.tween_property(title_box, "modulate:a", 0.0, 1.5)

# ---- Level loading ----
func load_level(idx: int) -> void:
  level_index = idx
  var data: Dictionary = levels[idx]
  level_name = data["name"]
  level_hint = data.get("hint", "")
  var rows: Array = data["rows"]
  var hrows: Array = data.get("heights", [])
  vines = data.get("vines", [])
  decor.clear()
  for d in data.get("decor", []):
    decor[d[0]] = d[1]   # d == [Vector2i(x, y), "sprite_name"]
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
  gesture_deltas.clear()   # fresh level: forget the recorded gesture (it persists across death, NOT load)
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

# ---- Attempt / recording ----
func _restart_attempt() -> void:
  mode = Mode.PLAY
  tick = 0
  player_cell = start_cell
  player_face = Vector2i.ZERO
  current_path = [start_cell]
  echoes.clear()   # continuous timeline can't be partially rewound — ghosts are wiped on death/reset
  won = false; banner.visible = false
  _snap_positions()
  _update_state()
  _update_hud()

func _begin_record() -> void:
  mode = Mode.RECORD
  rec_anchor = player_cell           # remember where player is standing NOW
  current_path = [player_cell]       # record starts from current position
  message = ""
  # No teleport, no tick reset — player stays put, timeline keeps running
  _update_state()
  _update_hud()

func _end_record() -> void:
  # RECORD now only BANKS a reusable clipboard shape — it does NOT spawn a ghost. The recorded
  # cells are stored as RELATIVE deltas from rec_anchor (deltas[0] == (0,0)). Later, _deploy()
  # stamps a ghost at the player's current cell that traces these deltas from there. So the same
  # shape can be stamped from many positions, and re-recording replaces the clipboard.
  if current_path.size() > 1:
    var deltas: Array = []
    for c in current_path:
      deltas.append((c as Vector2i) - rec_anchor)
    gesture_deltas = deltas
    message = "Gesture banked (%d steps). Walk somewhere, press E to deploy." % (deltas.size() - 1)
  else:
    message = "Nothing recorded — hold SPACE and walk to record a gesture."
  # Snap player back to where they were when they pressed SPACE — no level reset, no ghost.
  player_cell = rec_anchor
  mode = Mode.PLAY
  _snap_positions()
  _update_state()
  _update_hud()

func _deploy() -> void:
  # STAMP a ghost at the player's CURRENT cell tracing the banked clipboard shape from here.
  # anchor = player_cell (where you stand now), deltas = the clipboard (copied so re-recording
  # later can't mutate already-deployed ghosts), start_tick = tick so the ghost spawns under you
  # this instant and advances one delta per future player action, freezing on its last delta.
  # Does NOT consume the clipboard — stamp the same shape from as many spots as you like.
  if gesture_deltas.size() < 2:
    message = "Nothing recorded yet — hold SPACE and walk to record a gesture first."
    _update_hud()
    return
  echoes.append({"anchor": player_cell, "deltas": gesture_deltas.duplicate(), "start_tick": tick})
  message = "Ghost %d deployed." % echoes.size()
  _snap_positions()
  _update_state()
  _update_hud()

func _full_reset() -> void:
  load_level(level_index)

func _next_level() -> void:
  load_level((level_index + 1) % levels.size())

func _toggle_fullscreen() -> void:
  var m := DisplayServer.window_get_mode()
  if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
  else:
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---- Input ----
func _unhandled_key_input(event: InputEvent) -> void:
  if not (event is InputEventKey) or event.echo:
    return
  var k: int = event.keycode
  # Hold SPACE to record; release to bank.
  if k == KEY_SPACE:
    if event.pressed and mode == Mode.PLAY and not won:
      _begin_record()
    elif not event.pressed and mode == Mode.RECORD:
      _end_record()
    return
  if not event.pressed:
    return
  match k:
    KEY_R, KEY_T, KEY_BACKSPACE: _full_reset(); return
    KEY_N:
      if won: _next_level()
      return
    KEY_H:
      show_help = not show_help
      help.visible = show_help
      return
    KEY_F11:
      _toggle_fullscreen(); return
    KEY_ESCAPE:
      get_tree().change_scene_to_file("res://start_screen.tscn"); return
  if won or busy:
    return
  # E = deploy/echo: stamp a ghost of the banked gesture at the player's current cell.
  if k == KEY_E and mode == Mode.PLAY:
    _deploy(); return
  match k:
    KEY_UP, KEY_W: _move(Vector2i(0, -1))
    KEY_RIGHT, KEY_D: _move(Vector2i(1, 0))
    KEY_DOWN, KEY_S: _move(Vector2i(0, 1))
    KEY_LEFT, KEY_A: _move(Vector2i(-1, 0))

# ---- Movement ----
func _in_bounds(c: Vector2i) -> bool:
  return c.x >= 0 and c.x < grid_w and c.y >= 0 and c.y < grid_h

func _phys_walkable(cell: Vector2i) -> bool:
  if not floors.has(cell):
    return false
  return absi(_height(cell) - _height(player_cell)) <= max_climb

func _move(delta: Vector2i) -> void:
  var target := player_cell + delta
  if mode == Mode.RECORD:
    if _in_bounds(target):
      _advance(target, true)
  else:
    if _phys_walkable(target):
      _advance(target, false)

func _advance(new_cell: Vector2i, record: bool) -> void:
  player_pos_from = _player_draw()
  for i in range(echoes.size()):
    echo_pos_from[i] = _echo_draw(i)
  player_face = new_cell - player_cell
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
  if mode == Mode.PLAY:
    if hazards.has(player_cell):
      _die("You hit the spikes! Ghosts cleared — try again.")
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
  var deltas: Array = echo["deltas"]
  var anchor: Vector2i = echo["anchor"]
  var st: int = echo.get("start_tick", 0)
  # Anchor + the relative gesture: the ghost begins at the anchor the moment it's banked
  # and advances one delta per player action, freezing on its last delta (holding a switch).
  var idx: int = clamp(t - st, 0, deltas.size() - 1)
  return anchor + (deltas[idx] as Vector2i)

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
  var sc: float = SPR[sname].get("scale", 1.0)
  var anchor: Vector2 = SPR[sname]["anchor"]
  if sc == 1.0:
    draw_texture(tex[sname], pos - anchor)
  else:
    var sz := Vector2(tex[sname].get_size())
    draw_texture_rect(tex[sname], Rect2(pos - anchor * sc, sz * sc), false)
  return true

func _draw_column(top: Vector2, depth: float) -> void:
  var t := _diamond(top, tile_w, tile_h)
  var down := Vector2(0, depth)
  draw_colored_polygon(PackedVector2Array([t[3], t[2], t[2] + down, t[3] + down]), C_COL_L)
  draw_colored_polygon(PackedVector2Array([t[2], t[1], t[1] + down, t[2] + down]), C_COL_R)

func _draw_vine(x: float, y: float, length: float, seed: float) -> void:
  var segs := 6
  var step := length / segs
  var pts := PackedVector2Array()
  pts.append(Vector2(x, y))
  for i in range(1, segs + 1):
    var sway := sin(i * 1.3 + seed) * 7.0
    pts.append(Vector2(x + sway, y + step * i))
  draw_polyline(pts, Color(C_MOSS_D.r, C_MOSS_D.g, C_MOSS_D.b, 0.9), 2.6)
  for i in range(1, segs + 1):
    var sway2 := sin(i * 1.3 + seed) * 7.0
    var lp := Vector2(x + sway2 + (5 if i % 2 else -5), y + step * i)
    draw_circle(lp, 3.0, C_MOSS_M if i % 2 else C_MOSS_D)

# ---- Vector pawns ----
func _draw_stadium(cx: float, top: float, w: float, h: float, col: Color) -> void:
  var hw := w * 0.5
  if h > w:
    draw_rect(Rect2(cx - hw, top + hw, w, h - 2.0 * hw), col)
    draw_circle(Vector2(cx, top + hw), hw, col)
    draw_circle(Vector2(cx, top + h - hw), hw, col)
  else:
    draw_circle(Vector2(cx, top + h * 0.5), hw, col)

func _face_suffix(d: Vector2i) -> String:
  if d == Vector2i(1, 0): return "_se"
  if d == Vector2i(0, 1): return "_sw"
  if d == Vector2i(-1, 0): return "_nw"
  if d == Vector2i(0, -1): return "_ne"
  return "_s"

func _echo_face(i: int) -> Vector2i:
  var e: Dictionary = echoes[i]
  var step := _echo_pos(e, tick) - _echo_pos(e, tick - 1)
  if step == Vector2i.ZERO:   # frozen / not yet started -> face the way the shape last walked
    var dl: Array = e["deltas"]
    if dl.size() >= 2:
      step = (dl[dl.size() - 1] as Vector2i) - (dl[dl.size() - 2] as Vector2i)
  return step

func _draw_pawn(pos: Vector2, kind: int, face: Vector2i) -> void:
  var ghost := kind == 2
  var phase := kind == 1
  var a := echo_alpha if ghost else (0.82 if phase else 1.0)
  var sname := ("gh" if ghost else "pl") + _face_suffix(face)
  if not tex.has(sname):
    sname = ("gh" if ghost else "pl") + "_s"
  if tex.has(sname):
    draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
    draw_circle(Vector2.ZERO, 16.0, Color(0, 0, 0, (0.12 if ghost else 0.26) * a))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    var t: Texture2D = tex[sname]
    var sz := Vector2(t.get_size())
    draw_texture_rect(t, Rect2(pos - CHAR_ANCHOR * CHAR_SCALE, sz * CHAR_SCALE), false, Color(1, 1, 1, a))
    if ghost:
      draw_arc(Vector2(pos.x, pos.y - 24.0), 25.0, 0.0, TAU, 28, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.5 * a), 1.6)
    elif phase:
      draw_arc(Vector2(pos.x, pos.y - 24.0), 25.0, 0.0, TAU, 28, Color(C_PHASE_RING.r, C_PHASE_RING.g, C_PHASE_RING.b, 0.7), 1.8)
    return
  _draw_pawn_vector(pos, kind)

func _draw_pawn_vector(pos: Vector2, kind: int) -> void:
  var ghost := kind == 2
  var phase := kind == 1
  var body := C_GHOST if ghost else C_PLAYER
  var outline := C_GHOST.darkened(0.4) if ghost else C_PLAYER_OUTLINE
  var a := echo_alpha if ghost else (phase_alpha if phase else 1.0)
  var cx := pos.x
  draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
  draw_circle(Vector2.ZERO, 19.0, Color(0, 0, 0, (0.12 if ghost else 0.26) * a))
  draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
  var bw := 26.0
  var bh := 48.0
  var top := pos.y - bh - 3.0
  var headc := Vector2(cx, top - 6.0)
  _draw_stadium(cx, top - 2.0, bw + 4.0, bh + 4.0, Color(outline.r, outline.g, outline.b, a))
  draw_circle(headc, 13.0, Color(outline.r, outline.g, outline.b, a))
  _draw_stadium(cx, top, bw, bh, Color(body.r, body.g, body.b, a))
  draw_circle(headc, 11.0, Color(body.r, body.g, body.b, a))
  if not ghost:
    var hl := C_PLAYER.lightened(0.28)
    draw_circle(Vector2(cx - 5.0, headc.y - 2.0), 4.0, Color(hl.r, hl.g, hl.b, a))
  if ghost:
    draw_arc(Vector2(cx, top + bh * 0.4), 29.0, 0.0, TAU, 32, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.5 * a), 1.8)
  elif phase:
    draw_arc(Vector2(cx, top + bh * 0.4), 29.0, 0.0, TAU, 32, Color(C_PHASE_RING.r, C_PHASE_RING.g, C_PHASE_RING.b, 0.65), 1.8)

# ---- Rendering: one back-to-front painter pass ----
func _draw() -> void:
  draw_texture_rect(bg_tex, Rect2(Vector2.ZERO, get_viewport_rect().size), false)
  _draw_backdrop()
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

# Faint isometric floor expanse around the playable island so the level doesn't float in a void.
# Mossy-stone diamonds tile outward and fade to nothing with distance from the board centre,
# before the vignette (layer 5) darkens the edges. Purely cosmetic — never consulted by logic.
func _draw_backdrop() -> void:
  if grid_w == 0 or grid_h == 0:
    return
  var cx := (grid_w - 1) * 0.5
  var cy := (grid_h - 1) * 0.5
  var edge := maxf(cx, cy)
  var pad := 7
  for x in range(-pad, grid_w + pad):
    for y in range(-pad, grid_h + pad):
      if x >= 0 and x < grid_w and y >= 0 and y < grid_h:
        continue   # the real floor/wall pass owns the island itself
      var d := Vector2(x - cx, y - cy).length()
      var a := clampf(0.15 - (d - edge) * 0.017, 0.0, 0.15)
      if a <= 0.0:
        continue
      var c := _ground(Vector2i(x, y))
      var base := C_FLOOR if ((x + y) & 1) == 0 else C_FLOOR_EDGE
      var dia := _diamond(c, tile_w, tile_h)
      draw_colored_polygon(dia, Color(base.r, base.g, base.b, a))
      var ol := dia.duplicate(); ol.append(dia[0])
      draw_polyline(ol, Color(C_FLOOR_EDGE.r, C_FLOOR_EDGE.g, C_FLOOR_EDGE.b, a * 0.7), 1.0)

func _draw_pawns_at(s: int) -> void:
  for i in range(echoes.size()):
    var gc := _echo_pos(echoes[i], tick)
    if gc.x + gc.y == s:
      _draw_pawn(_echo_draw(i), 2, _echo_face(i))
  if player_cell.x + player_cell.y == s:
    _draw_pawn(_player_draw(), 1 if mode == Mode.RECORD else 0, player_face)

func _draw_floor(cell: Vector2i) -> void:
  var c := _surface(cell)
  var h := _height(cell)
  if h > 0:
    _draw_column(c, h * level_step)
  if hazards.has(cell):
    if not _blit("hazard", c):
      draw_colored_polygon(_diamond(c, tile_w, tile_h), Color("1d1b17"))
      for i in range(-1, 2):
        var tx := c.x + i * 20.0
        draw_colored_polygon(PackedVector2Array([
          Vector2(tx - 8, c.y + 4), Vector2(tx + 8, c.y + 4), Vector2(tx, c.y - 14)]), C_PIT_TEETH)
    return
  var variant := "floor_b" if ((cell.x + cell.y) % 2 == 1) else "floor_a"
  if not _blit(variant, c):
    if not _blit("floor_a", c):
      var dia := _diamond(c, tile_w, tile_h)
      draw_colored_polygon(dia, C_FLOOR)
      var ol := dia.duplicate(); ol.append(dia[0])
      draw_polyline(ol, C_FLOOR_EDGE, 2.0)
  if decor.has(cell):
    _blit(decor[cell], c)   # ground props (rubble, mushrooms, crystal...) sit on the floor
  if plates.has(cell):
    _blit("plate", c)
    var on: bool = pressed_plates.get(cell, false)
    var glow := C_PLATE_ON if on else C_PLATE
    var ga := 0.62 if on else 0.32
    draw_colored_polygon(_diamond(c, tile_w * 0.62, tile_h * 0.62), Color(glow.r, glow.g, glow.b, ga * 0.45))
    draw_colored_polygon(_diamond(c, tile_w * 0.42, tile_h * 0.42), Color(glow.r, glow.g, glow.b, ga))
    draw_colored_polygon(_diamond(c, tile_w * 0.18, tile_h * 0.18), Color(1, 1, 1, ga * 0.5))
  if cell == exit_cell:
    if exit_open:
      # active portal: light pools on the threshold, the open door, then a beam rising through it
      draw_colored_polygon(_diamond(c, tile_w * 0.78, tile_h * 0.78), Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.22))
      _blit("door_open", c)
      draw_colored_polygon(_diamond(c, tile_w * 0.34, tile_h * 0.34), Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.5))
      draw_colored_polygon(_diamond(c, tile_w * 0.16, tile_h * 0.16), Color(1, 1, 1, 0.45))
      var bw := tile_w * 0.16
      draw_colored_polygon(PackedVector2Array([
        c + Vector2(-bw, 0), c + Vector2(bw, 0),
        c + Vector2(bw * 0.55, -96.0), c + Vector2(-bw * 0.55, -96.0)]),
        Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.16))
    else:
      # sealed door — no glow, so a closed exit clearly reads as closed
      _blit("door_closed", c)

func _draw_wall(cell: Vector2i) -> void:
  var sname: String = decor.get(cell, "wall")   # mossy/cracked/crystal/brazier variants are full blocks
  if not _blit(sname, _ground(cell)) and not _blit("wall", _ground(cell)):
    var base := _ground(cell)
    var top := base - Vector2(0, wall_height)
    var b := _diamond(base, tile_w, tile_h)
    var t := _diamond(top, tile_w, tile_h)
    draw_colored_polygon(PackedVector2Array([t[3], t[2], b[2], b[3]]), C_WALL_L)
    draw_colored_polygon(PackedVector2Array([t[2], t[1], b[1], b[2]]), C_WALL_R)
    draw_colored_polygon(t, C_WALL_TOP)
    var ol := t.duplicate(); ol.append(t[0])
    draw_polyline(ol, C_WALL_TOP.darkened(0.4), 2.0)
  if vines.has(cell):
    var base2 := _ground(cell)
    _draw_vine(base2.x - tile_w * 0.22, base2.y - wall_height + 8.0, wall_height + 8.0, cell.x * 2.7 + cell.y * 1.9)

# ---- Path traces ----
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
    # Reconstruct the ghost's absolute cells from its anchor + relative deltas.
    var anchor: Vector2i = e["anchor"]
    var abs_path: Array = []
    for d in e["deltas"]:
      abs_path.append(anchor + (d as Vector2i))
    _draw_trace(abs_path, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.24), 2.0)
  if mode == Mode.RECORD and current_path.size() > 1:
    _draw_trace(current_path, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.9), 3.0)
  elif mode == Mode.PLAY and not won and gesture_deltas.size() >= 2:
    _draw_deploy_preview()

func _draw_deploy_preview() -> void:
  # Faint preview of where a deploy (E) would land: dotted shape anchored at the player's
  # CURRENT cell, plus a translucent ghost outline on its last delta (where the ghost freezes).
  var preview: Array = []
  for d in gesture_deltas:
    preview.append(player_cell + (d as Vector2i))
  _draw_trace(preview, Color(C_PHASE_RING.r, C_PHASE_RING.g, C_PHASE_RING.b, 0.30), 2.0)
  var landing: Vector2i = preview[preview.size() - 1]
  var lp := _surface(landing)
  # Reuse the ghost silhouette at low alpha so the player can read the resting pose.
  var lface := Vector2i.ZERO
  if gesture_deltas.size() >= 2:
    lface = (gesture_deltas[gesture_deltas.size() - 1] as Vector2i) - (gesture_deltas[gesture_deltas.size() - 2] as Vector2i)
  var ga := echo_alpha
  echo_alpha = 0.20
  _draw_pawn(lp, 2, lface)
  echo_alpha = ga

# ---- Minimal HUD ----
func _update_hud() -> void:
  var has_gesture := gesture_deltas.size() >= 2
  if plates.size() > 0:
    var pc := 0
    for p in plates:
      if pressed_plates.get(p, false):
        pc += 1
    status.text = "switches %d/%d    ghosts %d" % [pc, plates.size(), echoes.size()]
    if has_gesture:
      status.text += "    [gesture ready · E]"
    status.visible = true
  else:
    status.text = "ghosts %d" % echoes.size()
    if has_gesture:
      status.text += "    [gesture ready · E]"
    status.visible = echoes.size() > 0 or has_gesture
  var base := ""
  if mode == Mode.RECORD:
    base = "● RECORDING  —  walk through walls  ·  release SPACE to bank the gesture"
  elif has_gesture:
    base = "Press E to deploy a ghost at your position     ·     hold SPACE to re-record     ·     H help"
  else:
    base = "Hold SPACE and walk to record a gesture     ·     H help"
  if message != "":
    base = message + "        " + base
  prompt.text = base
