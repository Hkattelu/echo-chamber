extends Node
## Headless solvability + timing harness for Echo Chamber (top-down redesign).
##
## Instances main.tscn, forces move_time tiny, then drives a DATA-DRIVEN table of
## solution "cases" through the game's OWN public methods (load_level / _begin_record /
## _move / _end_record / _deploy). For every case it records won, the final tick, and the
## per-ghost timing margin (moves-after-deploy minus deltas.size()-1) and asserts the
## expected win state. Results are written to res://_verify_results.txt (stdout is NOT
## reliable — the tree quits before it flushes), then the app quits.
##
## HOW THE TIER C-E AGENT REUSES THIS: append entries to CASES below — one dict per case:
##   {"level": <int>, "name": <String>, "expect_won": <bool>, "steps": [ <step>, ... ]}
## Steps are arrays whose first element is an opcode:
##   ["rec"]                  begin recording a gesture at the current cell
##   ["mv", dx, dy]           one move (dx,dy in {-1,0,1}); during RECORD it phases through walls
##   ["mv", dx, dy, n]        n identical moves
##   ["end"]                  release/bank the recorded gesture into the clipboard (NO ghost)
##   ["dep"]                  deploy a ghost of the banked gesture at the current cell
## A case always starts fresh (load_level re-inits and clears the clipboard). To prove a
## naive attempt fails, give it expect_won=false and assert on that (see L7 short / L8 naive).
## Run headless:  godot --headless --path <project> _verify.tscn

const RESULT_PATH := "res://_verify_results.txt"

var CASES := [
  {"level": 0, "name": "L1 First Step", "expect_won": true, "steps": [
    ["rec"], ["mv",0,1], ["end"], ["mv",0,1], ["mv",1,0], ["dep"],
    ["mv",1,0], ["mv",1,0], ["mv",0,1], ["mv",0,1]]},

  {"level": 1, "name": "L2 Sealed", "expect_won": true, "steps": [
    ["mv",0,1], ["rec"], ["mv",0,1], ["mv",0,1], ["end"], ["dep"],
    ["mv",-1,0,3], ["mv",0,1,4], ["mv",1,0,3], ["mv",0,1]]},

  {"level": 2, "name": "L3 Spikes", "expect_won": true, "steps": [
    ["mv",1,0,4], ["mv",0,1,2], ["rec"], ["mv",0,1], ["mv",0,1], ["end"], ["dep"],
    ["mv",0,-1,2], ["mv",1,0,4]]},

  {"level": 3, "name": "L4 Twice", "expect_won": true, "steps": [
    ["rec"], ["mv",0,-1], ["end"],
    ["mv",-1,0,2], ["mv",0,-1], ["dep"],
    ["mv",1,0,4], ["dep"],
    ["mv",0,1], ["mv",-1,0,2], ["mv",0,1,2]]},

  {"level": 4, "name": "L5 Chorus", "expect_won": true, "steps": [
    ["mv",0,1], ["mv",-1,0,3], ["rec"], ["mv",0,1], ["mv",0,1], ["end"], ["dep"],
    ["mv",1,0,4], ["dep"],
    ["mv",1,0,4], ["dep"],
    ["mv",-1,0,2], ["mv",0,1,4], ["mv",-1,0,3], ["mv",0,1]]},

  {"level": 5, "name": "L6 Sealed Gauntlet", "expect_won": true, "steps": [
    ["mv",0,1], ["mv",1,0,3], ["rec"], ["mv",0,1], ["mv",0,1], ["end"], ["dep"],
    ["mv",-1,0,3], ["mv",0,1,4], ["mv",1,0,3], ["mv",0,1,2]]},

  {"level": 6, "name": "L7 The Long Way (SHORT route)", "expect_won": false, "steps": [
    ["rec"], ["mv",1,0,6], ["mv",0,-1,6], ["end"], ["dep"], ["mv",1,0,2]]},

  {"level": 6, "name": "L7 The Long Way (LONG route)", "expect_won": true, "steps": [
    ["rec"], ["mv",1,0,6], ["mv",0,-1,6], ["end"], ["dep"],
    ["mv",0,-1,6], ["mv",1,0,6], ["mv",0,1,6], ["mv",-1,0,4]]},

  {"level": 7, "name": "L8 Off-Center (NAIVE anchor)", "expect_won": false, "steps": [
    ["rec"], ["mv",0,1], ["mv",0,1], ["end"], ["mv",0,1], ["dep"],
    ["mv",-1,0,3], ["mv",0,1,4], ["mv",1,0,3], ["mv",0,1]]},

  {"level": 7, "name": "L8 Off-Center (CORRECT anchor)", "expect_won": true, "steps": [
    ["rec"], ["mv",0,1], ["mv",0,1], ["end"], ["mv",0,1], ["mv",-1,0], ["dep"],
    ["mv",-1,0,2], ["mv",0,1,4], ["mv",1,0,3], ["mv",0,1]]},

  {"level": 8, "name": "L9 Crossroads Refined", "expect_won": true, "steps": [
    ["mv",1,0,4], ["mv",0,1], ["rec"], ["mv",0,1], ["mv",0,1], ["mv",0,1], ["mv",0,1], ["end"], ["dep"],
    ["mv",0,-1], ["mv",1,0,4]]},

  # ===== TIER C (levels 10-14, indices 9-13) — TWO+ distinct recorded shapes required =====

  # L10 needs an L-shape (right2,up3) for the high switch and a straight (down3) for the low one.
  {"level": 9, "name": "L10 Two Shapes (SOLVE, 2 shapes)", "expect_won": true, "steps": [
    ["mv",1,0,2],
    ["rec"], ["mv",1,0,2], ["mv",0,-1,3], ["end"], ["dep"],
    ["mv",1,0,2],
    ["rec"], ["mv",0,1,3], ["end"], ["dep"],
    ["mv",1,0,4]]},
  # NAIVE: bank ONE shape (the L) and stamp it twice — the second ghost lands on a wall, not S2.
  {"level": 9, "name": "L10 Two Shapes (NAIVE single shape)", "expect_won": false, "steps": [
    ["mv",1,0,2],
    ["rec"], ["mv",1,0,2], ["mv",0,-1,3], ["end"], ["dep"],
    ["mv",1,0,2], ["dep"],
    ["mv",1,0,4]]},

  # L11: go DEEP first, plant the slow ghost (right4), climb back, plant the near ghost (left4), exit.
  {"level": 10, "name": "L11 Order Matters (SOLVE, 2 shapes)", "expect_won": true, "steps": [
    ["mv",0,1,6],
    ["rec"], ["mv",1,0,4], ["end"], ["dep"],
    ["mv",0,-1,4],
    ["rec"], ["mv",-1,0,4], ["end"], ["dep"],
    ["mv",0,1,6]]},

  # L12 elevation: ghosts hold the two height-2 shelf switches; the player must CLIMB the ramp to exit.
  {"level": 11, "name": "L12 Vault Above (SOLVE, 2 shapes + climb)", "expect_won": true, "steps": [
    ["mv",0,1,2], ["mv",1,0,3],
    ["rec"], ["mv",0,-1,1], ["end"], ["dep"],
    ["mv",0,1,2],
    ["rec"], ["mv",-1,0,2], ["end"], ["dep"],
    ["mv",1,0,2], ["mv",0,1,1], ["mv",1,0,3]]},
  # BLOCKED: both switches are held, but reaching the exit from the flat side is a +2 cliff. The player
  # ends at (9,5) right beside the door and cannot step up — proving the height is load-bearing.
  {"level": 11, "name": "L12 Vault Above (BLOCKED cliff, no climb)", "expect_won": false, "steps": [
    ["mv",0,1,2], ["mv",1,0,3],
    ["rec"], ["mv",0,-1,1], ["end"], ["dep"],
    ["mv",0,1,2],
    ["rec"], ["mv",-1,0,2], ["end"], ["dep"],
    ["mv",1,0,5], ["mv",0,1,1]]},

  # L13: three switches at three rows -> three banked shapes (down4, up4, L). Aisle row 5 dodges the pit.
  {"level": 12, "name": "L13 Three Shapes (SOLVE, 3 shapes)", "expect_won": true, "steps": [
    ["mv",0,-1,1], ["mv",1,0,2],
    ["rec"], ["mv",0,1,4], ["end"], ["dep"],
    ["mv",1,0,2],
    ["rec"], ["mv",0,-1,4], ["end"], ["dep"],
    ["mv",1,0,2],
    ["rec"], ["mv",1,0,2], ["mv",0,-1,2], ["end"], ["dep"],
    ["mv",1,0,4], ["mv",0,1,1]]},

  # L14: bank the reach AND its true mirror (left3 then right3), deploy both from the column, exit.
  {"level": 13, "name": "L14 The Divide (SOLVE, shape + mirror)", "expect_won": true, "steps": [
    ["mv",0,1,3],
    ["rec"], ["mv",-1,0,3], ["end"], ["dep"],
    ["rec"], ["mv",1,0,3], ["end"], ["dep"],
    ["mv",0,1,4]]},
  # NAIVE MIRROR: bank the SAME left reach twice — both ghosts land on the left switch, right stays open.
  {"level": 13, "name": "L14 The Divide (NAIVE same-gesture mirror)", "expect_won": false, "steps": [
    ["mv",0,1,3],
    ["rec"], ["mv",-1,0,3], ["end"], ["dep"],
    ["rec"], ["mv",-1,0,3], ["end"], ["dep"],
    ["mv",0,1,4]]},

  # ===== TIER D (levels 15-17, indices 14-16) =====

  # L15: cross the ground, CLIMB the ramp 0-1-2-3 to the bridge, plant two ghosts on the h5 spires, exit.
  {"level": 14, "name": "L15 Ledge Run (SOLVE, climb + 2 shapes)", "expect_won": true, "steps": [
    ["mv",1,0,10],
    ["mv",0,-1,3],
    ["mv",-1,0,5],
    ["rec"], ["mv",1,0,2], ["mv",0,-1,1], ["end"], ["dep"],
    ["mv",-1,0,3],
    ["rec"], ["mv",0,-1,1], ["end"], ["dep"],
    ["mv",-1,0,2]]},

  # L16: plant the quick left ghost, plant the deep up7 ghost near the door, then LOOP to buy it time.
  {"level": 15, "name": "L16 Narrow Margins (SOLVE, detour)", "expect_won": true, "steps": [
    ["mv",0,-1,4],
    ["rec"], ["mv",-1,0,2], ["end"], ["dep"],
    ["mv",0,1,4], ["mv",1,0,2],
    ["rec"], ["mv",0,-1,7], ["end"], ["dep"],
    ["mv",0,-1,4], ["mv",1,0,2], ["mv",0,1,4]]},
  # NAIVE FAST ROUTE: dash the 2 steps straight to the door — the deep ghost is still 5 ticks out.
  {"level": 15, "name": "L16 Narrow Margins (NAIVE fast route)", "expect_won": false, "steps": [
    ["mv",0,-1,4],
    ["rec"], ["mv",-1,0,2], ["end"], ["dep"],
    ["mv",0,1,4], ["mv",1,0,2],
    ["rec"], ["mv",0,-1,7], ["end"], ["dep"],
    ["mv",1,0,2]]},

  # L17: 4 switches, 3 shapes. up2 is banked once and stamped on S1 AND S2; then up4 (S3), down2 (S4).
  {"level": 16, "name": "L17 The Foundry (SOLVE, 3 shapes / 4 switches)", "expect_won": true, "steps": [
    ["mv",1,0,1],
    ["rec"], ["mv",0,-1,2], ["end"], ["dep"],
    ["mv",1,0,4], ["dep"],
    ["mv",1,0,4],
    ["rec"], ["mv",0,-1,4], ["end"], ["dep"],
    ["mv",1,0,2],
    ["rec"], ["mv",0,1,2], ["end"], ["dep"],
    ["mv",1,0,3]]},
]

var _lines: Array = []

func _ready() -> void:
  _run_all()

func _run_all() -> void:
  var scene: PackedScene = load("res://main.tscn")
  var main = scene.instantiate()
  add_child(main)
  main.move_time = 0.0001
  await get_tree().process_frame
  var all_ok := true
  for c in CASES:
    var ok = await _run_case(main, c)
    if not ok:
      all_ok = false
  _lines.append("")
  _lines.append("ALL CASES PASSED" if all_ok else "*** SOME CASES FAILED ***")
  _write()
  await get_tree().process_frame
  get_tree().quit(0 if all_ok else 1)

func _run_case(main, c) -> bool:
  var lvl = c["level"]
  main.load_level(lvl)
  await get_tree().process_frame
  await get_tree().process_frame
  for step in c["steps"]:
    await _do_step(main, step)
  # --- gather results (plain var: := fails on Variant reads off the main scene) ---
  var won = main.won
  var tick = main.tick
  var echoes = main.echoes
  var lvl_name = main.level_name
  var grid = "%dx%d" % [main.grid_w, main.grid_h]
  var expect = c["expect_won"]
  var pass_ok = (won == expect)
  # switches held count
  var held = 0
  var total = 0
  var plates = main.plates
  var pressed = main.pressed_plates
  for p in plates:
    total += 1
    if pressed.get(p, false):
      held += 1
  var head = "[%s] %s  (%s %s)  won=%s expect=%s  switches=%d/%d  finalTick=%d" % [
    "PASS" if pass_ok else "FAIL", c["name"], lvl_name, grid, str(won), str(expect), held, total, tick]
  _lines.append(head)
  var gi = 0
  for e in echoes:
    var st = e["start_tick"]
    var dl = e["deltas"]
    var needed = dl.size() - 1
    var elapsed = tick - st
    var margin = elapsed - needed
    var rest = e["anchor"] + dl[dl.size() - 1]
    _lines.append("      ghost %d: deployTick=%d needed=%d movesAfter=%d margin=%d rests=%s" % [
      gi + 1, st, needed, elapsed, margin, str(rest)])
    gi += 1
  return pass_ok

func _do_step(main, step) -> void:
  var op = step[0]
  match op:
    "rec":
      main._begin_record()
    "end":
      main._end_record()
    "dep":
      main._deploy()
    "mv":
      var dx = step[1]
      var dy = step[2]
      var n = 1
      if step.size() > 3:
        n = step[3]
      for i in range(n):
        main._move(Vector2i(dx, dy))
        await _wait_idle(main)
  await get_tree().process_frame

func _wait_idle(main) -> void:
  var guard = 0
  while main.busy and guard < 40:
    await get_tree().process_frame
    guard += 1
  # one extra frame so _after_step's win/state update has definitely run
  await get_tree().process_frame

func _write() -> void:
  var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
  if f == null:
    return
  for ln in _lines:
    f.store_line(ln)
  f.flush()
  f.close()
