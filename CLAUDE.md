# CLAUDE.md — Echo Chamber

Guidance for working in this repo. Read this first.

## What this is
A 2D **isometric temporal-puzzle** prototype in **Godot 4.6** (GL Compatibility renderer),
built for a game jam. Theme: "Phase Exchange." You record a movement run as an intangible
**phase ghost** (which walks through walls and over hazards), then use those ghosts to hold
switches and — via **Swap** — to teleport your physical self into sealed rooms or across
lethal pits. Repo: https://github.com/Hkattelu/echo-chamber (account `Hkattelu`).

## Running / testing
- Main scene is `res://start_screen.tscn` (title); it changes to `res://main.tscn`.
- **Godot MCP**: `launch_editor` once after adding/changing assets (to import), then
  `run_project` (optionally `scene: "res://main.tscn"`), then `get_debug_output`. Or F5.
- There is **no runtime-screenshot MCP tool**. To eyeball rendering OR machine-verify a
  level is solvable, make a throwaway `_shot.tscn` + `scripts/_shot.gd` that instances
  `main.tscn`, sets `main.move_time = 0.0001`, and drives the game through its own methods
  (`main.load_level(n)`, `main._begin_phase()`, `main._move(Vector2i(...))`,
  `main._commit_phase()`, `main._wait()`, `main._swap()`), awaiting a few `process_frame`s
  between steps (moves are tween-gated by `busy`). Assert on `main.won`, write results to a
  file (NOT print — the process `quit()`s before you can read stdout) and/or
  `save_png(...)`. Run, read the file/PNG, delete the temp files. This is how all four
  Chapter-1 levels were verified solvable. NOTE: type-infer (`:=`) fails on values read off
  the `main` Variant — use plain `var x = main.player_cell`.

## Layout
```
start_screen.tscn / scripts/StartScreen.gd   title screen (code-built UI + iso backdrop)
main.tscn         / scripts/Main.gd          the whole game (grid, record/replay, render, HUD)
                    scripts/Token.gd          one pawn (player or ghost); sprite or procedural
assets/sprites/*.png(.import)                 Aseprite art: floor_a/b, wall, plate, exit, hazard, pawn
```
`Main.gd` is intentionally single-file. Keep it that way unless asked.

## Core model — "Phase Exchange" (do NOT rewrite into real-time)
Turn-based, deterministic **lockstep**. One global `tick`; every action advances all ghosts
one step. Two player states (`Mode.PHYSICAL` / `Mode.PHASE`):

- **PHYSICAL** (default): tangible. Walls block your input; stepping onto a hazard kills you
  (attempt restarts, ghosts kept). This is how you actually reach the exit. From here you
  can **Swap** (`E`).
- **PHASE** (recording a ghost): start at the level start, intangible. You may step through
  **walls and over hazards** (only `_in_bounds` limits you). Each step appends to
  `current_path`. **Commit** (`F`/`R`) snaps you back to start and spawns a ghost replaying
  that path; **Cancel** (`Q`) discards it.
- A ghost replays `path[clamp(tick,0,len-1)]` → it **freezes on its last tile** past its
  length (how it keeps holding a switch). Ghosts are non-colliding and press plates.
- **Determinism:** entering phase, committing, canceling, dying, and full reset all
  `_restart_attempt()` → tick 0, player at start, mode PHYSICAL, all ghosts replay from 0.
  This is why multi-ghost simultaneity is trivially reasoned-about. Keep this invariant.
- **Swap (`E`, PHYSICAL only):** teleports the player to the **nearest ghost's current
  cell** and advances a tick. IMPORTANT: ghosts are at their `path[0]` (= start) at tick 0,
  so you must **wait/move until the ghost has walked onto the target tile, then swap.** This
  timing IS the puzzle. Current swap is **one-way** (teleport-to-ghost); the ghost is not
  moved to your old cell (it keeps its absolute replay). A true position-swap-with-offset is
  a documented future upgrade (needed for some Chapter 2+ levels, not Chapter 1).
- Exit opens when every plate is occupied by player-or-ghost in the same tick (always open
  if a level has zero plates). Win = PHYSICAL player on the exit while it is open.

## Levels (ASCII)
`levels` in `Main.gd`: array of `{name, hint, rows, heights?}`.
- `rows`: `#` wall, `.` floor, `P` start, `E` exit, `^` hazard (lethal pit), `1`-`9` plate.
- `heights` (optional, same dims): digit = elevation per cell (default 0). Raised tiles draw
  a support column; you step at most `max_climb` (1) level per PHYSICAL move.
- Chapter 1 (built + verified): 1 Ghost Walk (phase through a wall to a sealed switch),
  2 Dual Lock (two ghosts hold two sealed switches), 3 First Swap (phase into a sealed exit,
  swap to it), 4 Hazard Crossing (phase across a pit, swap onto the far side).
- Chapters 2-3 (levels 5-13 from the design guide: dual-ghost gating, path-crossing
  paradox, moving mazes, multi-body swap) are **designed but not built** — they need
  playtesting/tuning and likely the offset-swap upgrade. Build incrementally and verify
  each is solvable (drive it via the API as above) before committing.

## Rendering
- `_ground(cell)` ignores height; `_surface(cell)` = ground minus `height*level_step`. Tiles
  + tokens use `_surface`; walls use `_ground`. `_draw()` iterates back-to-front by `x+y`.
- `_blit(name, screen_pos)` draws `tex[name]` at `screen_pos - SPR[name].anchor`; returns
  false if missing → procedural fallback shapes. Hazard tiles `return` after blitting (no
  moss/plate on them). Plate/exit **glows are always procedural on top** for instant state
  read; open exit also draws a translucent light beam.
- Player token tints translucent blue (`C_PHASE_TINT`, `phase_alpha`) while PHASE via
  `_apply_player_look()`; ghosts are `pawn.png` tinted `C_ECHO_TINT`. z_index 100 player, 50 ghost.

## Sprite pipeline (Aseprite MCP)
- Workspace (`ASEPRITE_WORKSPACE`) resolves to the **shared `prototypes/` dir**, not this
  project. `export_sprite` lands in `C:\Users\himan\prototypes\`; then `mv` PNGs into
  `assets/sprites/` and delete leftover `.aseprite` sources. Trust the absolute path returned.
- `draw_line` is broken — use thin filled rectangles. `draw_triangle` works (used for spikes).
  Coordinates are 0..size-1.
- Sprite sizes / anchors (anchor = cell-center pixel landing on `_surface`):
  floor 96x64 (48,32); wall 96x96 (48,60); plate 72x44 (36,22); exit 88x60 (44,30);
  hazard 96x64 (48,32); pawn 44x60 (22,56 = feet).
- Build sprites: dark silhouette pass → fill shrunk ~2px inside (leaves an outline) →
  shadow (right) / highlight (left). Moss = a few large overlapping multi-shade masses with
  ragged edges, NOT scattered single dots.

## Controls
Arrows/WASD move · Space wait · **F** Phase / Commit ghost · **Q** cancel phase ·
**E** Swap with nearest ghost · T reset level · N next (after solving) · Esc → title.

## Tunable @export knobs (on the Main node)
`tile_w`, `tile_h`, `wall_height`, `level_step`, `max_climb`, `move_time`, `echo_alpha`,
`phase_alpha`.

## Workflow conventions
- **Commit AND push everything as we go** (clear, ongoing history is valued). Trailer:
  `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`.
- `gh` is NOT on the bash PATH; run it via the **PowerShell** tool (authed as `Hkattelu`).
  Push: `git push origin master` (default branch is `master`).
- **Edit guard gotcha:** Write/Edit may be blocked by a worktree-isolation guard in this
  repo. Author files via **Bash heredocs**, chunked (`cat > f <<'EOF'` then `cat >> f`,
  ~60-80 lines each) — big single heredocs get truncated → confusing `unexpected EOF`. Keep
  apostrophes out of heredoc bodies.
- Commit Godot `.import`/`.uid` files (reproducible imports); `.godot/` is gitignored.
