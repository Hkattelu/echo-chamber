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
