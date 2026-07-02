extends Node2D
## ECHO CHAMBER — 2D top-down temporal-puzzle prototype.
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
# TOP-DOWN renderer. tile_size is the on-screen square edge of one cell. The whole board is
# auto-scaled DOWN from this if a level is too big to fit the 1280x720 base (see _recompute_layout),
# so bigger future levels stay fully on-screen.
@export var tile_size: int = 96
@export var max_climb: int = 1             # SIMULATION knob (kept): max height step a solid player may climb, see _phys_walkable.
@export var char_scale_frac: float = 1.3   # character sprite height as a multiple of the fitted tile size
@export var move_time: float = 0.10
@export var echo_alpha: float = 0.62
@export var phase_alpha: float = 0.5
# Elevation is shown WITHOUT lifting pawns up the screen (that reads as "floating" in flat top-down,
# which is why the iso `level_step`/`wall_height` positional exports were removed). Instead each
# height band tints its floor a step brighter and a subtle ledge line is drawn on the downhill edges
# of a raised cell. All current levels are height 0 (flat), so this stays invisible until a level
# actually populates `heights` — it exists and is correct, just not exercised yet.
@export var elev_tint_step: float = 0.17   # per-height-band floor brightening (raised from 0.09: at
                                           # 0.09 the bands were indistinguishable in playtest screenshots)

# ---- Palette (worn overgrown tower) ----
const C_FLOOR := Color("9ea08d")
const C_FLOOR_EDGE := Color("585a47")
const C_WALL_TOP := Color("8b8d78")
const C_WALL_L := Color("62644e")
const C_WALL_R := Color("4c4e3a")
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

# Sprites are loaded LAZILY BY NAME from res://assets/sprites/<name>.png (Image.load_from_file at
# runtime, so they render even without .import files). This keeps the renderer projection-agnostic
# and the decor dict fully generic — a level may name ANY sprite and it just blits (missing = skip).
const SPRITE_DIR := "res://assets/sprites/"
# The required top-down set the parallel asset pass provides; pre-warmed in _load_textures. Anything
# else (decor props a level names) is lazy-loaded on first blit. td_* = top-down tiles/decals;
# pl_/gh_ = player / ghost-echo characters (cardinal facings + idle).
const REQUIRED_SPRITES := [
  "td_floor_a", "td_floor_b", "td_wall", "td_hazard", "td_plate", "td_door_closed", "td_door_open",
  "pl_n", "pl_e", "pl_s", "pl_w", "gh_n", "gh_e", "gh_s", "gh_w",
]
# Foot anchor as a FRACTION of the sprite's own size (robust to native px): centre-x, ~85% down.
const CHAR_FOOT := Vector2(0.5, 0.85)
# Subtle per-deploy-order tints (multiplied over the purple ghost sprite) so ghost 1/2/3 read apart.
const GHOST_TINTS := [Color("cbbcff"), Color("bcd6ff"), Color("ffc7e6"), Color("c4eccd"), Color("ffe6ad")]
var tex := {}          # name -> Texture2D (loaded & cached)
var tex_absent := {}   # name -> true (known missing; don't re-stat the filesystem every frame)
var _ts: float = 96.0  # fitted on-screen tile edge in px (recomputed per level in _recompute_layout)
var _max_height := 0   # tallest height band in the current level (0 = flat -> skip elevation draws)
var bg_tex: GradientTexture2D

enum Mode { PLAY, RECORD }

func _hash(n: float) -> float:
  var s := sin(n * 127.1 + 311.7) * 43758.5453
  return s - floor(s)

# ---- Levels ( # wall, . floor, P start, E exit, ^ spike pit, 1-9 switches ).
#      Optional: vines ([Vector2i] wall cells with a hanging vine). ----
var levels := [
  {
    "name": "First Step",
    "hint": "Record a short walk, then deploy it wherever you like — the ghost repeats your walk from there.",
    "rows": [
      "#########",
      "#.......#",
      "#..P....#",
      "#.......#",
      "#...1...#",
      "#.....E.#",
      "#########"],
    "decor": [
      [Vector2i(1, 1), "td_crystal"], [Vector2i(7, 1), "td_ferns"],
      [Vector2i(1, 5), "td_mushrooms"], [Vector2i(7, 2), "td_rubble"],
    ],
  },
  {
    "name": "Sealed",
    "hint": "This switch is sealed in — the walls only loosen their grip while you're recording.",
    "rows": [
      "#########",
      "#...P...#",
      "#.......#",
      "#.#####.#",
      "#.#.1.#.#",
      "#.#####.#",
      "#.......#",
      "#...E...#",
      "#########"],
    "decor": [
      [Vector2i(1, 1), "td_crystal"], [Vector2i(7, 1), "td_ferns"],
      [Vector2i(1, 6), "td_mushrooms"], [Vector2i(7, 6), "td_rubble"],
      [Vector2i(7, 2), "td_brazier"],
    ],
  },
  {
    "name": "Spikes",
    "hint": "The spikes will kill you but not your echo. Let it take the dangerous path while you keep to safe ground.",
    "rows": [
      "###########",
      "#P.......E#",
      "#.........#",
      "#.........#",
      "#^^^^^^^^^#",
      "#....1....#",
      "###########"],
    "decor": [
      [Vector2i(2, 1), "td_crystal"], [Vector2i(1, 2), "td_ferns"],
      [Vector2i(7, 2), "td_rubble"], [Vector2i(7, 1), "td_mushrooms"],
    ],
  },
  {
    "name": "Twice",
    "hint": "You only need to record once. The same banked shape drops a fresh echo wherever you stand — so where should each one come to rest?",
    "rows": [
      "#########",
      "#.......#",
      "#.1...2.#",
      "#.......#",
      "#...P...#",
      "#.......#",
      "#...E...#",
      "#########"],
    "decor": [
      [Vector2i(1, 4), "td_crystal"], [Vector2i(7, 4), "td_ferns"],
      [Vector2i(1, 5), "td_mushrooms"], [Vector2i(7, 5), "td_rubble"],
      [Vector2i(4, 1), "td_brazier"],
    ],
  },
  {
    "name": "Chorus",
    "hint": "Three switches, boxed by the same mold. Bank one reach and it will fit them all.",
    "rows": [
      "#############",
      "#.....P.....#",
      "#...........#",
      "#.###.###.###",
      "#.#1#.#2#.#3#",
      "#.###.###.###",
      "#...........#",
      "#.....E.....#",
      "#############"],
    "decor": [
      [Vector2i(1, 1), "td_crystal"], [Vector2i(11, 1), "td_ferns"],
      [Vector2i(1, 6), "td_mushrooms"], [Vector2i(11, 6), "td_rubble"],
      [Vector2i(2, 1), "td_brazier"],
    ],
  },
  {
    "name": "Sealed Gauntlet",
    "hint": "The switch is walled in and the floor bites back. Record your way inside, then find the one safe seam to the door.",
    "rows": [
      "#########",
      "#P......#",
      "#.......#",
      "#.#####.#",
      "#.#.1.#.#",
      "#.#####.#",
      "#.......#",
      "#^^^.^^^#",
      "#...E...#",
      "#########"],
    "decor": [
      [Vector2i(7, 1), "td_crystal"], [Vector2i(7, 2), "td_ferns"],
      [Vector2i(2, 1), "td_mushrooms"], [Vector2i(6, 2), "td_rubble"],
    ],
  },
  {
    "name": "The Long Way",
    "hint": "The door is only a few steps away — but your echo has a long road to walk. Don't leave before it arrives.",
    "rows": [
      "#########",
      "#......1#",
      "#.#####.#",
      "#.#####.#",
      "#.#####.#",
      "#.#####.#",
      "#.#####.#",
      "#P.E....#",
      "#########"],
    "decor": [
      [Vector2i(4, 1), "td_crystal"], [Vector2i(1, 4), "td_ferns"],
      [Vector2i(7, 4), "td_mushrooms"], [Vector2i(5, 7), "td_rubble"],
    ],
  },
  {
    "name": "Off-Center",
    "hint": "A shape lands cell-for-cell from where you deploy — the ghost stops exactly where your steps say, not merely close. Line it up.",
    "rows": [
      "###########",
      "#....P....#",
      "#.........#",
      "#...###...#",
      "#..#1..#..#",
      "#...###...#",
      "#.........#",
      "#....E....#",
      "###########"],
    "decor": [
      [Vector2i(1, 1), "td_crystal"], [Vector2i(9, 1), "td_ferns"],
      [Vector2i(1, 6), "td_mushrooms"], [Vector2i(9, 6), "td_rubble"],
    ],
  },
  {
    "name": "Crossroads, Refined",
    "hint": "Spikes and walls both yield to your echo but not to you. Send one straight through — and be sure you've walked far enough before you reach the door.",
    "rows": [
      "###########",
      "#P.......E#",
      "#.........#",
      "#^^^^^^^^^#",
      "#.........#",
      "#...###...#",
      "#...#1#...#",
      "#...###...#",
      "###########"],
    "decor": [
      [Vector2i(2, 1), "td_crystal"], [Vector2i(7, 1), "td_ferns"],
      [Vector2i(1, 7), "td_mushrooms"], [Vector2i(9, 7), "td_rubble"],
    ],
  },
  # ===== TIER C — multi-shape mastery (10-14): the clipboard is replaced mid-level, so a
  #       single banked gesture can no longer cover every switch. =====
  {
    "name": "Two Shapes",
    "hint": "One switch sits high, the other low — a single reach can't touch both ends of the room. Bank one shape, then bank another.",
    # Reachable ground is the single corridor row. S1 is 3 rows ABOVE it, S2 3 rows BELOW: their
    # required vertical offsets are opposite, so NO one gesture lands on both (proven forcing).
    "rows": [
      "###########",
      "#####1#####",
      "###########",
      "###########",
      "#P.......E#",
      "###########",
      "###########",
      "#####2#####",
      "###########"],
    "decor": [
      [Vector2i(1, 1), "td_crystal"], [Vector2i(9, 1), "td_ferns"],
      [Vector2i(1, 7), "td_mushrooms"], [Vector2i(9, 7), "td_rubble"],
    ],
  },
  {
    "name": "Order Matters",
    "hint": "Two switches on opposite walls, each wanting its own reach — and the far one is slow to arrive. Plant the patient ghost before you double back.",
    # One narrow column is all you can stand on. S1 is 4 cells LEFT, S2 is 4 cells RIGHT — opposite
    # offsets, so two banked shapes are unavoidable. The deep ghost must be stamped first or it never
    # reaches its plate in time: a there-and-back route, not a single sweep.
    "rows": [
      "###########",
      "#####P#####",
      "#####.#####",
      "#1###.#####",
      "#####.#####",
      "#####.#####",
      "#####.#####",
      "#####.###2#",
      "#####.#####",
      "#####E#####",
      "###########"],
    "decor": [
      [Vector2i(2, 1), "td_crystal"], [Vector2i(8, 1), "td_ferns"],
      [Vector2i(2, 9), "td_mushrooms"], [Vector2i(8, 9), "td_rubble"],
    ],
  },
  {
    "name": "The Vault Above",
    "hint": "Two switches perch on shelves a stride too tall to climb — an echo never had to obey the height. The door itself sits high: find the slope that lets you rise, not the wall that won't.",
    # ELEVATION is load-bearing here. S1 (4,2) and S2 (2,5) are open floor but height 2: a solid step
    # up is +2 (over max_climb=1), so only a phasing-recorded ghost can rest on them. The EXIT (9,6)
    # is height 2 and reachable ONLY by the climbable ramp 0->1->2 at (7,6)->(8,6)->(9,6); every other
    # approach to it is a +2 cliff the player cannot mount. (See the two _verify cases: the winning run
    # climbs the ramp; the blocked run reaches (9,5) beside the door but cannot step up the cliff.)
    "rows": [
      "###########",
      "#P........#",
      "#...1.....#",
      "#.........#",
      "#.........#",
      "#.2.......#",
      "#........E#",
      "#.........#",
      "###########"],
    "heights": [
      "00000000000",
      "00000000000",
      "00002000000",
      "00000000000",
      "00000000000",
      "00200000000",
      "00000001220",
      "00000000000",
      "00000000000"],
    "decor": [
      [Vector2i(7, 1), "td_crystal"], [Vector2i(1, 7), "td_ferns"],
      [Vector2i(5, 7), "td_mushrooms"], [Vector2i(8, 3), "td_rubble"],
    ],
  },
  {
    "name": "Three Shapes",
    "hint": "Three switches, three heights above and below the aisle — no single reach spans them. Bank three gestures, and mind the pit that splits the floor.",
    # Only the two-row aisle (rows 5-6) is standing ground; a spike pit bites the middle of row 6, so
    # the player weaves up to row 5 to cross. The three sealed switches sit at rows 1, 3 and 9 — far
    # enough apart that their required offsets never overlap, forcing THREE distinct banked shapes
    # (up4, an L, down4). Verified solvable (margins 13/7/1).
    "rows": [
      "#############",
      "#####1#######",
      "#############",
      "#########2###",
      "#############",
      "#...........#",
      "#P...^^^...E#",
      "#############",
      "#############",
      "###3#########",
      "#############"],
    "decor": [
      [Vector2i(2, 1), "td_crystal"], [Vector2i(10, 1), "td_ferns"],
      [Vector2i(1, 7), "td_mushrooms"], [Vector2i(11, 7), "td_rubble"],
    ],
  },
  {
    "name": "The Divide",
    "hint": "A mirror-perfect hall, a sealed switch on either flank. The temptation is to bank one reach and echo it both ways — but a deployed shape only slides, it never flips.",
    # LOOKS symmetric, ISN'T solvable by mirroring. The only footing is the 1-wide column x=6, so a
    # left-reaching gesture ALWAYS rests to the left, no matter where you stand — repeating it can
    # never reach the right switch. You must bank the reach AND its true opposite (left3 then right3).
    # The naive "same gesture twice" case proves it fails (both ghosts pile on S1).
    "rows": [
      "#############",
      "######P######",
      "######.######",
      "######.######",
      "###1##.##2###",
      "######.######",
      "######.######",
      "######.######",
      "######E######",
      "#############"],
    "decor": [
      [Vector2i(2, 1), "td_crystal"], [Vector2i(10, 1), "td_ferns"],
      [Vector2i(2, 8), "td_mushrooms"], [Vector2i(10, 8), "td_rubble"],
    ],
  },
  # ===== TIER D — precision & scale (15-17) =====
  {
    "name": "The Ledge Run",
    "hint": "A spike chasm cuts the low ground from the high walk. Only the far slope rises step by step — climb it, then plant your echoes on the two spires the walk can't touch.",
    # MULTIPLE height bands. Low ground (row 5, h0) and the high bridge (row 2, h3) are split by a two-
    # row spike moat; the ONLY crossing is the ramp column x=11 rising 0->1->2->3 (each step climbable).
    # S1 (3,1) and S2 (8,1) are h5 spires above the h3 bridge — +2, so only phasing ghosts rest there,
    # via two different reaches (up1, and an L). Load-bearing: without the climb the bridge is a h3 cliff.
    "rows": [
      "#############",
      "###1####2####",
      "#E..........#",
      "#^^^^^^^^^^.#",
      "#^^^^^^^^^^.#",
      "#P..........#",
      "#############",
      "#############"],
    "heights": [
      "0000000000000",
      "0005000050000",
      "3333333333330",
      "0000000000020",
      "0000000000010",
      "0000000000000",
      "0000000000000",
      "0000000000000"],
    "decor": [
      [Vector2i(2, 6), "td_crystal"], [Vector2i(10, 6), "td_ferns"],
      [Vector2i(4, 7), "td_mushrooms"], [Vector2i(8, 7), "td_rubble"],
    ],
  },
  {
    "name": "Narrow Margins",
    "hint": "The door is a breath away from where you plant the last echo — but that echo has the whole hall to climb. Rush it and you arrive alone. Take the long road.",
    # PURE TIMING. S2 (5,1) is deep: its ghost needs 7 ticks to crawl up. Deploying it from (5,8) leaves
    # the exit (7,8) only 2 steps away, so the naive dash arrives 5 ticks early (see the NAIVE _verify
    # case, won=false). The winning run loops the room to burn ticks. S1 (1,4) is a quick left-reach.
    "rows": [
      "###########",
      "#####2#####",
      "###########",
      "###########",
      "#1#.......#",
      "###.......#",
      "###.......#",
      "###.......#",
      "###P...E..#",
      "###########"],
    "decor": [
      [Vector2i(9, 4), "td_crystal"], [Vector2i(9, 6), "td_ferns"],
      [Vector2i(4, 7), "td_mushrooms"], [Vector2i(8, 4), "td_rubble"],
    ],
  },
  {
    "name": "The Foundry",
    "hint": "Four switches scattered off one long gallery, no two at the same reach. Read them all before you bank a thing — two share a mold, two do not.",
    # NON-SYMMETRIC read-the-room test. Only the gallery (row 5) is walkable. S1 (2,3) & S2 (6,3) sit
    # two up (SAME shape, stamped twice); S3 (10,1) is four up; S4 (12,7) is two DOWN. Four switches,
    # three distinct banked shapes (up2 x2, up4, down2). Verified solvable (margins 17/13/3/1).
    "rows": [
      "#################",
      "##########3######",
      "#################",
      "##1###2##########",
      "#################",
      "#P.............E#",
      "#################",
      "############4####",
      "#################"],
    "decor": [
      [Vector2i(4, 1), "td_crystal"], [Vector2i(14, 1), "td_ferns"],
      [Vector2i(3, 7), "td_mushrooms"], [Vector2i(14, 7), "td_rubble"],
    ],
  },
  # ===== TIER E — capstones (18-20) =====
  {
    "name": "The Choir",
    "hint": "Five voices, but only two songs. The same reach means one thing up here and another thing over there — it is only ever a question of where you stand to sing it.",
    # THE THESIS LEVEL. Exactly TWO gestures: up2 (stamped on the three upper switches from below each)
    # and down2 (stamped on the two lower switches). Five switches, two shapes — the whole game in one
    # room: a gesture means something different depending on where you plant it. Verified (margins 19..1).
    "rows": [
      "#################",
      "#################",
      "##1####2####3####",
      "#################",
      "#P.............E#",
      "#################",
      "####4#####5######",
      "#################",
      "#################"],
    "decor": [
      [Vector2i(5, 1), "td_crystal"], [Vector2i(9, 1), "td_ferns"],
      [Vector2i(2, 7), "td_mushrooms"], [Vector2i(14, 7), "td_rubble"],
    ],
  },
  {
    "name": "The Long Climb",
    "hint": "From the floor there is a buried switch below you and two spires far overhead, and a spike chasm between. Plant what you can down here, take the one slope up, and spend the whole walk home paying off the slowest echo.",
    # Largest room. Combines: a ground sealed switch (down2), a two-row spike moat crossed only by the
    # x13 ramp climbing 0-1-2-3 (load-bearing), and two h5 spire switches on the high bridge needing an
    # L then an up2. Three distinct shapes; the L ghost is planted first so the long walk to the far
    # door pays off its timing. Verified solvable (margins 30/4/1).
    "rows": [
      "###############",
      "####2####3#####",
      "###############",
      "#E............#",
      "#^^^^^^^^^^^^.#",
      "#^^^^^^^^^^^^.#",
      "#P............#",
      "###############",
      "##1############",
      "###############",
      "###############"],
    "heights": [
      "000000000000000",
      "000050000500000",
      "000000000000000",
      "033333333333330",
      "000000000000020",
      "000000000000010",
      "000000000000000",
      "000000000000000",
      "000000000000000",
      "000000000000000",
      "000000000000000"],
    "decor": [
      [Vector2i(6, 2), "td_crystal"], [Vector2i(11, 2), "td_ferns"],
      [Vector2i(4, 10), "td_mushrooms"], [Vector2i(10, 10), "td_rubble"],
    ],
  },
  {
    "name": "The Tower's Heart",
    "hint": "Two sealed switches, one patient and one quick, both stamped from the heart of the tower — and the door lies up a short slope beyond. The order you bank them in is the whole puzzle: give your slow echo its head start.",
    # THE FINALE — deploy ORDER is the puzzle. Because RECORDING advances the clock, whichever gesture
    # you bank first gets a head start. From the hub (3,7) you must record+stamp the SLOW up4 BEFORE the
    # quick down2, then climb the ramp to the door (6,7,h2) — only 3 steps away. Record them in the wrong
    # order and the slow echo is one step short (see the WRONG-ORDER _verify case, won=false). Also here:
    # sealed switches, a height-2 door reachable only by its ramp (a +2 cliff blocks the far approach),
    # and a spike-guarded dead end past it. Verified: correct order margins 1/1; wrong order fails.
    "rows": [
      "###########",
      "###########",
      "###########",
      "###1#######",
      "###########",
      "###########",
      "###########",
      "#P....E.^.#",
      "###########",
      "###2#######",
      "###########"],
    "heights": [
      "00000000000",
      "00000000000",
      "00000000000",
      "00000000000",
      "00000000000",
      "00000000000",
      "00000000000",
      "00000120000",
      "00000000000",
      "00000000000",
      "00000000000"],
    "decor": [
      [Vector2i(6, 3), "td_crystal"], [Vector2i(8, 3), "td_ferns"],
      [Vector2i(6, 9), "td_mushrooms"], [Vector2i(1, 5), "td_rubble"],
    ],
  },
  # ===== BONUS — switch-gated door (Part 4 stretch). A post-finale coda that introduces the ONE
  #       new mechanic 1-20 never used: a door (lowercase 'a', linked to switch 1) that is passable
  #       ONLY while its switch is held. =====
  {
    "name": "Coda",
    "hint": "The heart has a second chamber, sealed behind a barred door — and the door only yields while its outer switch is pressed. Set a keeper on it before you cross, then seal the way beyond from within.",
    # DOOR mechanic debut. The middle wall (x=6) has ONE opening: the door 'a' at (6,5), gated by
    # switch 1 (3,2) out in the near room. The EXIT (11,5) sits in the far chamber, reachable ONLY
    # through that door — so you MUST deploy a ghost onto switch 1 to hold the door open before you
    # can walk across (naive proof: walk straight at the door with nothing on switch 1 and it stays
    # shut). The far chamber holds a second sealed switch 2 (9,2) the exit also needs; you deploy its
    # ghost from inside (9,4) — a spot you can only reach once the door is open. One banked shape
    # (up2) serves both switches; the sequence, not the shape, is the puzzle. Verified: 3 harness
    # cases (solve won, gate-closed naive lost, missing-switch-2 naive lost).
    "rows": [
      "#############",
      "#.....#..#..#",
      "#..1..#.#2#.#",
      "#.....#..#..#",
      "#.....#.....#",
      "#.....a....E#",
      "#.....#.....#",
      "#P....#.....#",
      "#############"],
    "decor": [
      [Vector2i(1, 1), "td_crystal"], [Vector2i(5, 1), "td_ferns"],
      [Vector2i(11, 1), "td_rubble"], [Vector2i(11, 7), "td_mushrooms"],
    ],
  },
]

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
  "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI"]
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
var gates := {}   # cell (Vector2i) -> linked plate cell. A switch-gated DOOR: a floor cell that blocks
                  # PLAY movement while its linked switch is unheld (open iff pressed_plates[link]). State
                  # is DERIVED each tick from switch occupancy, not stored — so death/reset needs no special
                  # casing. RECORD phases through it (like a wall); ghost replay ignores it (pure geometry).
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
  get_viewport().size_changed.connect(_on_viewport_resized)
  _load_textures()
  _build_bg()
  _build_vignette()
  _build_hud()
  load_level(0)

func _on_viewport_resized() -> void:
  # "expand" stretch can change the reported viewport on non-16:9 windows — re-centre the board.
  _recompute_layout()
  _snap_positions()

func _load_textures() -> void:
  for sname in REQUIRED_SPRITES:
    _get_tex(sname)   # pre-warm the required set; any missing ones just take the procedural fallback

# Lazy texture fetch by name -> res://assets/sprites/<name>.png. Caches hits AND misses, so a
# missing sprite (the procedural-fallback path, or a decor prop this build doesn't ship) is only
# stat'd once, not every frame. Projection-agnostic: never touches iso/ortho geometry.
func _get_tex(sname: String) -> Texture2D:
  if tex.has(sname):
    return tex[sname]
  if tex_absent.has(sname):
    return null
  var path := SPRITE_DIR + sname + ".png"
  var abs_path := ProjectSettings.globalize_path(path)
  var p := abs_path if FileAccess.file_exists(abs_path) else path
  if FileAccess.file_exists(p):
    var img := Image.load_from_file(p)
    if img != null:
      var t := ImageTexture.create_from_image(img)
      tex[sname] = t
      return t
  tex_absent[sname] = true
  return null

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
  help.text = "CONTROLS\nMove: Arrows / WASD\nHold SPACE: record a gesture (walk through walls) — release to bank it as a reusable shape\nE: deploy — stamp a ghost at your position that traces the banked gesture (stamp from anywhere, as often as you like)\nQ: wait — advance a beat without moving (stall for timing; while recording it banks a pause the ghost repeats)\nRe-record (hold SPACE again) to replace the banked gesture.\nR / T: reset level    N: next (after solving)\nF11: fullscreen    Esc: title    H: hide help"
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
  walls.clear(); floors.clear(); hazards.clear(); heights.clear(); plates.clear(); gates.clear()
  won = false; banner.visible = false; message = ""
  grid_h = rows.size()
  grid_w = (rows[0] as String).length()
  # Doors ('a'/'b'/'c') link to the same-numbered switch (a->1, b->2, c->3). A door may be scanned
  # before its switch, so collect [cell, num] and resolve to the switch's cell after the full pass.
  var plate_num := {}       # digit int -> plate cell
  var gate_pending: Array = []
  for y in range(grid_h):
    var line: String = rows[y]
    for x in range(line.length()):
      var cell := Vector2i(x, y)
      var ch := line[x]
      if ch == "#":
        walls[cell] = true
        continue
      floors[cell] = true   # doors are floor cells too (walkable when open, phaseable when recording)
      var hgt := 0
      if hrows.size() > y and x < (hrows[y] as String).length():
        hgt = (hrows[y] as String)[x].to_int()
      heights[cell] = hgt
      match ch:
        "P": start_cell = cell
        "E": exit_cell = cell
        "^": hazards[cell] = true
        "1", "2", "3", "4", "5", "6", "7", "8", "9":
          plates.append(cell)
          plate_num[ch.to_int()] = cell
        "a": gate_pending.append([cell, 1])
        "b": gate_pending.append([cell, 2])
        "c": gate_pending.append([cell, 3])
  for gp in gate_pending:
    if plate_num.has(gp[1]):
      gates[gp[0]] = plate_num[gp[1]]   # door cell -> its linked switch's cell
  _max_height = 0
  for h in heights.values():
    _max_height = maxi(_max_height, int(h))
  _recompute_layout()
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

func _wait() -> void:
  # Advance ONE tick without moving. Not-moving is always legal, so this bypasses _move's
  # delta/walkability check and calls _advance directly (win/state/hazard checks still run in
  # _after_step, exactly as for a real step). In PLAY it's a deliberate stall for timing puzzles;
  # in RECORD it appends the current cell again (a duplicate delta), which the replay math
  # deltas[clamp(...)] already supports — a recorded pause makes the deployed ghost hold a beat,
  # so pausing genuinely enriches recordable shapes. Facing is preserved (a stationary beat
  # shouldn't snap the pawn round to idle-front).
  var f := player_face
  _advance(player_cell, mode == Mode.RECORD)
  player_face = f

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
  # Q = wait: advance a tick in place. In PLAY it's a timing stall; in RECORD it records a pause.
  if k == KEY_Q:
    _wait(); return
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
  # Switch-gated door: blocks PLAY movement while its linked switch is unheld. RECORD phases through
  # (that path never calls _phys_walkable), and ghost replay ignores walkability entirely.
  if gates.has(cell) and not pressed_plates.get(gates[cell], false):
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

# ---- Orthogonal top-down transform ----
# Fit the grid_w x grid_h board into the base viewport. tile_size is the ideal cell edge; if the
# level is too big to fit (with a ~1-cell margin) _ts shrinks so the whole board stays visible.
func _recompute_layout() -> void:
  var vp := get_viewport_rect().size
  var margin := 1.0
  var fit_w: float = vp.x / maxf(1.0, float(grid_w) + margin * 2.0)
  var fit_h: float = vp.y / maxf(1.0, float(grid_h) + margin * 2.0)
  _ts = minf(float(tile_size), minf(fit_w, fit_h))
  var center := Vector2((grid_w - 1) * 0.5, (grid_h - 1) * 0.5)
  board_offset = vp * 0.5 - center * _ts

# _ground(c) = the CENTRE of cell c in screen space. board_offset centres the whole grid.
func _ground(c: Vector2i) -> Vector2:
  return Vector2(c.x, c.y) * _ts + board_offset

# Pawns stand at the cell centre. Elevation NO LONGER shifts screen position (that read as floating
# in flat top-down); height is shown via floor tint + ledge lines instead. Kept as a named helper so
# the pawn/trace draw code reads clearly ("where this actor stands").
func _surface(c: Vector2i) -> Vector2:
  return _ground(c)

# Axis-aligned square of side `edge`, centred on `center` — the top-down replacement for the diamond.
func _cell_rect(center: Vector2, edge: float) -> Rect2:
  return Rect2(center - Vector2(edge, edge) * 0.5, Vector2(edge, edge))

# Draw a tile/decal/prop sprite stretched to fill the cell's square (times `frac`, centred), so any
# source resolution maps cleanly onto the fitted tile. Returns false if the sprite is missing, so the
# caller draws a procedural fallback (or, for decor, just skips). Projection-agnostic.
func _blit_tile(sname: String, cell: Vector2i, frac := 1.0, mod := Color.WHITE) -> bool:
  var t := _get_tex(sname)
  if t == null:
    return false
  draw_texture_rect(t, _cell_rect(_ground(cell), _ts * frac), false, mod)
  return true

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
  if d == Vector2i(1, 0): return "_e"
  if d == Vector2i(0, 1): return "_s"
  if d == Vector2i(-1, 0): return "_w"
  if d == Vector2i(0, -1): return "_n"
  return "_s"   # idle -> face the camera

func _echo_face(i: int) -> Vector2i:
  var e: Dictionary = echoes[i]
  var step := _echo_pos(e, tick) - _echo_pos(e, tick - 1)
  if step == Vector2i.ZERO:   # frozen / not yet started -> face the way the shape last walked
    var dl: Array = e["deltas"]
    if dl.size() >= 2:
      step = (dl[dl.size() - 1] as Vector2i) - (dl[dl.size() - 2] as Vector2i)
  return step

# kind: 0 = solid player, 1 = recording (phasing) player, 2 = ghost. idx = deploy order for ghosts
# (-1 = player / preview) -> drives the subtle per-ghost tint + numeral badge.
func _draw_pawn(pos: Vector2, kind: int, face: Vector2i, idx := -1) -> void:
  var ghost := kind == 2
  var phase := kind == 1
  var a := echo_alpha if ghost else (0.82 if phase else 1.0)
  var mod := Color(1, 1, 1, a)
  if ghost and idx >= 0:
    var tnt: Color = GHOST_TINTS[idx % GHOST_TINTS.size()]   # subtle per-deploy-order hue step
    mod = Color(tnt.r, tnt.g, tnt.b, a)
  var t := _get_tex(("gh" if ghost else "pl") + _face_suffix(face))
  if t == null:
    t = _get_tex(("gh" if ghost else "pl") + "_s")
  if t != null:
    var sz := Vector2(t.get_size())
    var csc: float = (char_scale_frac * _ts) / maxf(1.0, sz.y)
    var anchor := Vector2(sz.x * CHAR_FOOT.x, sz.y * CHAR_FOOT.y)
    # flattened contact shadow at the feet
    draw_set_transform(pos, 0.0, Vector2(1.0, 0.45))
    draw_circle(Vector2.ZERO, _ts * 0.22, Color(0, 0, 0, (0.12 if ghost else 0.26) * a))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    draw_texture_rect(t, Rect2(pos - anchor * csc, sz * csc), false, mod)
    var ring_y := pos.y - _ts * 0.42
    if ghost:
      draw_arc(Vector2(pos.x, ring_y), _ts * 0.28, 0.0, TAU, 28, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.5 * a), 1.6)
    elif phase:
      draw_arc(Vector2(pos.x, ring_y), _ts * 0.28, 0.0, TAU, 28, Color(C_PHASE_RING.r, C_PHASE_RING.g, C_PHASE_RING.b, 0.7), 1.8)
    if ghost and idx >= 0 and echoes.size() >= 2:
      _draw_ghost_badge(pos - Vector2(0, char_scale_frac * _ts * 0.92), idx + 1)
    return
  _draw_pawn_vector(pos, kind)

# Tiny numbered badge above a ghost's head so several stacked echoes stay individually readable.
func _draw_ghost_badge(pos: Vector2, n: int) -> void:
  var r := maxf(7.0, _ts * 0.12)
  draw_circle(pos, r, Color(0.10, 0.08, 0.16, 0.85))
  draw_arc(pos, r, 0.0, TAU, 20, Color(C_GHOST.r, C_GHOST.g, C_GHOST.b, 0.9), 1.5)
  var f := ThemeDB.fallback_font
  if f == null:
    return
  var fs := int(r * 1.5)
  var s := str(n)
  var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
  draw_string(f, pos + Vector2(-tw.x * 0.5, tw.y * 0.32), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.96, 1.0, 0.96))

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

# ---- Rendering: flat top-down, clean back-to-front LAYERS (no iso occlusion to resolve) ----
func _draw() -> void:
  draw_texture_rect(bg_tex, Rect2(Vector2.ZERO, get_viewport_rect().size), false)
  _draw_backdrop()
  # 1) floor tiles + grid lines + per-height tint (row-major)
  for y in range(grid_h):
    for x in range(grid_w):
      var cell := Vector2i(x, y)
      if floors.has(cell):
        _draw_floor(cell)
  # 2) elevation ledges between cells of differing height (no-op on the current flat levels)
  if _max_height > 0:
    _draw_ledges()
  # 3) floor decals (hazards / switch plates / exit door), drawn on top of the floor
  for y in range(grid_h):
    for x in range(grid_w):
      var cell := Vector2i(x, y)
      if floors.has(cell):
        _draw_decals(cell)
  # 4) walls — flat blocks, no vertical face (one tile, full stop)
  for y in range(grid_h):
    for x in range(grid_w):
      var cell := Vector2i(x, y)
      if walls.has(cell):
        _draw_wall(cell)
  # 5) decor props (sparse; wall-variant decor is handled inside _draw_wall). Never over a
  #    switch/exit/hazard so clarity is preserved; missing sprite = quietly skipped.
  for y in range(grid_h):
    for x in range(grid_w):
      var cell := Vector2i(x, y)
      if floors.has(cell) and decor.has(cell) and not plates.has(cell) and cell != exit_cell and not hazards.has(cell) and not gates.has(cell):
        _blit_tile(decor[cell], cell, 0.9)
  # 6) ghost trail overlays — above floor/decor, UNDER pawns, so they never hide behind geometry
  _draw_paths()
  # 7) pawns (player + ghosts), radially staggered when several share a cell
  _draw_all_pawns()

# Flat surround: a faint square-tile motif a few cells beyond the playable board, fading with
# distance so the level doesn't float in a void (the vignette on layer 5 darkens the outer edge
# further). Purely cosmetic — never consulted by logic. Replaces the old iso diamond tiling.
func _draw_backdrop() -> void:
  if grid_w == 0 or grid_h == 0:
    return
  var cx := (grid_w - 1) * 0.5
  var cy := (grid_h - 1) * 0.5
  var edge := maxf(cx, cy)
  var pad := 6
  for x in range(-pad, grid_w + pad):
    for y in range(-pad, grid_h + pad):
      if x >= 0 and x < grid_w and y >= 0 and y < grid_h:
        continue   # the real floor/wall pass owns the island itself
      var d := Vector2(x - cx, y - cy).length()
      var a := clampf(0.16 - (d - edge) * 0.02, 0.0, 0.16)
      if a <= 0.0:
        continue
      var base := C_FLOOR if ((x + y) & 1) == 0 else C_FLOOR_EDGE
      var r := _cell_rect(_ground(Vector2i(x, y)), _ts)
      draw_rect(r, Color(base.r, base.g, base.b, a))
      draw_rect(r, Color(C_BG_OUT.r, C_BG_OUT.g, C_BG_OUT.b, a * 0.7), false, 1.0)

# Subtle "step-down" cue between a raised cell and a lower / off-grid neighbour: only the HIGHER
# cell draws, on the shared edge, so it reads as a small ledge. Drawn over floors, under decals.
func _draw_ledges() -> void:
  var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
  var half := _ts * 0.5
  for cell in floors.keys():
    var h := _height(cell)
    if h <= 0:
      continue
    var c := _ground(cell)
    for d in dirs:
      var nb: Vector2i = cell + d
      var nh: int = _height(nb) if floors.has(nb) else 0
      if nh >= h:
        continue
      var mid := c + Vector2(d.x, d.y) * half
      var perp := Vector2(-d.y, d.x) * half
      # Stronger than the original 0.30/0.10: a dark drop-shadow line on the downhill edge plus a lit
      # lip just inside the higher cell, so a raised tier reads clearly against the busy floor texture.
      draw_line(mid - perp, mid + perp, Color(0, 0, 0, 0.55), maxf(3.0, _ts * 0.09))
      var inw := Vector2(d.x, d.y) * (_ts * 0.07)
      draw_line(mid - perp - inw, mid + perp - inw, Color(1, 1, 1, 0.24), maxf(2.0, _ts * 0.04))

# Draw every pawn: ghosts (kind 2) plus the player (kind 0 PLAY / 1 RECORD). When several pawns
# share a logical cell they'd overlap exactly, so stagger them on a small deterministic radial ring
# for legibility. Sorted by screen-y so lower (front) pawns overlap higher (back) ones naturally.
func _draw_all_pawns() -> void:
  var by_cell := {}
  for i in range(echoes.size()):
    var gc: Vector2i = _echo_pos(echoes[i], tick)
    if not by_cell.has(gc):
      by_cell[gc] = []
    by_cell[gc].append({"i": i, "kind": 2})
  if not by_cell.has(player_cell):
    by_cell[player_cell] = []
  by_cell[player_cell].append({"i": -1, "kind": 1 if mode == Mode.RECORD else 0})
  var entries := []
  for cell in by_cell.keys():
    var lst: Array = by_cell[cell]
    var n := lst.size()
    for j in range(n):
      var e: Dictionary = lst[j]
      var pi: int = e["i"]
      var base_pos: Vector2 = _echo_draw(pi) if pi >= 0 else _player_draw()
      var off := Vector2.ZERO
      if n > 1:
        var ang := TAU * float(j) / float(n) - PI * 0.5
        var rad := _ts * 0.20
        off = Vector2(cos(ang) * rad, sin(ang) * rad * 0.6)
      var face: Vector2i = _echo_face(pi) if pi >= 0 else player_face
      entries.append({"pos": base_pos + off, "kind": int(e["kind"]), "face": face, "idx": pi})
  entries.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
  for e in entries:
    _draw_pawn(e["pos"], e["kind"], e["face"], e["idx"])

# Floor TILE only (decals are a separate pass): the checker tile, a per-height brightening tint,
# and a thin low-alpha grid line on every edge — the highest-value legibility win for a puzzle with
# several stacked translucent actors.
func _draw_floor(cell: Vector2i) -> void:
  var h := _height(cell)
  var tint := 1.0 + elev_tint_step * float(clampi(h, 0, 5))
  var mod := Color(tint, tint, tint, 1.0)
  var variant := "td_floor_b" if ((cell.x + cell.y) % 2 == 1) else "td_floor_a"
  if not _blit_tile(variant, cell, 1.0, mod):
    if not _blit_tile("td_floor_a", cell, 1.0, mod):
      draw_rect(_cell_rect(_ground(cell), _ts), C_FLOOR.lightened(clampf(tint - 1.0, 0.0, 0.6)))
  draw_rect(_cell_rect(_ground(cell), _ts), Color(C_FLOOR_EDGE.r, C_FLOOR_EDGE.g, C_FLOOR_EDGE.b, 0.22), false, 1.0)

# Floor decals drawn on top of the floor tile (below walls/pawns): hazard pit, switch plate, exit.
func _draw_decals(cell: Vector2i) -> void:
  var c := _ground(cell)
  if hazards.has(cell):
    if not _blit_tile("td_hazard", cell):
      _draw_hazard_fallback(cell)
    return
  if plates.has(cell):
    if not _blit_tile("td_plate", cell):
      draw_rect(_cell_rect(c, _ts * 0.74), Color(0.16, 0.19, 0.18, 0.9))
    var on: bool = pressed_plates.get(cell, false)
    var glow := C_PLATE_ON if on else C_PLATE
    var ga := 0.62 if on else 0.30
    draw_rect(_cell_rect(c, _ts * 0.60), Color(glow.r, glow.g, glow.b, ga * 0.45))
    draw_rect(_cell_rect(c, _ts * 0.40), Color(glow.r, glow.g, glow.b, ga))
    draw_rect(_cell_rect(c, _ts * 0.16), Color(1, 1, 1, ga * 0.5))
  if cell == exit_cell:
    if exit_open:
      draw_rect(_cell_rect(c, _ts * 0.92), Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.20))
      if not _blit_tile("td_door_open", cell):
        draw_rect(_cell_rect(c, _ts * 0.72), Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.55))
      draw_rect(_cell_rect(c, _ts * 0.30), Color(C_EXIT_ON.r, C_EXIT_ON.g, C_EXIT_ON.b, 0.5))
      draw_rect(_cell_rect(c, _ts * 0.14), Color(1, 1, 1, 0.5))
    else:
      if not _blit_tile("td_door_closed", cell):
        # sealed door — dark barred block, no glow, so a closed exit clearly reads as closed
        draw_rect(_cell_rect(c, _ts * 0.82), Color(C_EXIT.r, C_EXIT.g, C_EXIT.b, 0.85))
        draw_rect(_cell_rect(c, _ts * 0.82), Color(0, 0, 0, 0.55), false, 2.0)
  if gates.has(cell):
    _draw_gate(cell, pressed_plates.get(gates[cell], false))

# Switch-gated door (distinct from the EXIT door): closed = a solid dark barrier with vertical teal
# bars, clearly impassable; open = the floor shows through with only teal side-jambs + a frame, so a
# glance tells you whether it's passable and which state you're seeing.
func _draw_gate(cell: Vector2i, is_open: bool) -> void:
  var c := _ground(cell)
  var r := _cell_rect(c, _ts)
  if is_open:
    var jam := _ts * 0.13
    var col := Color(C_PLATE_ON.r, C_PLATE_ON.g, C_PLATE_ON.b, 0.55)
    draw_rect(Rect2(r.position, Vector2(jam, r.size.y)), col)
    draw_rect(Rect2(Vector2(r.end.x - jam, r.position.y), Vector2(jam, r.size.y)), col)
    draw_rect(r, Color(C_PLATE_ON.r, C_PLATE_ON.g, C_PLATE_ON.b, 0.45), false, 2.0)
  else:
    draw_rect(_cell_rect(c, _ts * 0.96), Color(0.10, 0.13, 0.13, 0.94))
    var bw := _ts * 0.10
    for i in range(4):
      var fx := r.position.x + _ts * (0.15 + 0.235 * float(i))
      draw_rect(Rect2(fx, r.position.y + _ts * 0.09, bw, _ts * 0.82), Color(C_PLATE.r, C_PLATE.g, C_PLATE.b, 0.95))
    draw_rect(_cell_rect(c, _ts * 0.96), Color(C_PLATE_ON.r, C_PLATE_ON.g, C_PLATE_ON.b, 0.4), false, 2.0)

func _draw_hazard_fallback(cell: Vector2i) -> void:
  var c := _ground(cell)
  draw_rect(_cell_rect(c, _ts), Color("1d1b17"))
  var n := 3
  for i in range(n):
    var tx := c.x + (float(i) - float(n - 1) * 0.5) * (_ts * 0.24)
    var half := _ts * 0.10
    draw_colored_polygon(PackedVector2Array([
      Vector2(tx - half, c.y + _ts * 0.12),
      Vector2(tx + half, c.y + _ts * 0.12),
      Vector2(tx, c.y - _ts * 0.18)]), C_PIT_TEETH)
  draw_rect(_cell_rect(c, _ts), Color(0, 0, 0, 0.5), false, 1.0)

# Flat wall block: one tile, no vertical face / column, no sprite bleed into neighbours. A subtle
# bevel (dark border + lit inset face) is drawn procedurally when the sprite is missing.
func _draw_wall(cell: Vector2i) -> void:
  var sname: String = decor.get(cell, "td_wall")   # wall-variant decor (if any) replaces the block
  if not _blit_tile(sname, cell) and not _blit_tile("td_wall", cell):
    var r := _cell_rect(_ground(cell), _ts)
    draw_rect(r, C_WALL_R)                              # dark base / border
    draw_rect(_cell_rect(_ground(cell), _ts * 0.9), C_WALL_TOP)   # lit face inset (stays in-cell)

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
    base = "● RECORDING  —  walk through walls  ·  Q pause  ·  release SPACE to bank the gesture"
  elif has_gesture:
    base = "Press E to deploy a ghost at your position     ·     hold SPACE to re-record     ·     Q wait     ·     H help"
  else:
    base = "Hold SPACE and walk to record a gesture     ·     Q wait     ·     H help"
  if message != "":
    base = message + "        " + base
  prompt.text = base
