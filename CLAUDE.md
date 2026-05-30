# CLAUDE.md — Echo Chamber

Guidance for working in this repo. Read this first.

## What this is
A 2D **isometric puzzle** prototype in **Godot 4.6** (GL Compatibility renderer), built for a
game jam. Worn, overgrown-tower look (Claude Design handoff): mossy olive stone, **Portal
palette** (orange player, translucent purple ghosts, teal switches/exit), heavy vignette,
minimal isolating HUD. Core mechanic is **motion record**: hold SPACE to record a ghost of
your walk, release to bank it; stack ghosts to hold switches and open the exit.
Repo: https://github.com/Hkattelu/echo-chamber (account Hkattelu).

## Running / testing
- Main scene is res://start_screen.tscn (title); it changes to res://main.tscn. The window is
  **fullscreen** by default (F11 toggles; Esc on the title quits).
- **Godot MCP**: launch_editor once after adding/changing assets (to import), then run_project
  (optionally scene: res://main.tscn), then get_debug_output. Or F5.
- **No runtime-screenshot MCP tool.** To eyeball rendering OR machine-verify a level is
  solvable, make a throwaway _shot.tscn + scripts/_shot.gd that instances main.tscn, sets
  main.move_time = 0.0001, and drives the game via its own methods: load_level(n),
  _begin_record(), _move(Vector2i(...)), _end_record(), plain _move(...) in PLAY. Await a few
  process_frames between steps (moves are tween-gated by busy). Assert on main.won; write
  results to a FILE (not print — the scene quits before stdout is readable) and/or save_png().
  Run, read, delete temp files. NOTE: := type-infer fails on values read off the main Variant —
  use plain var. Screenshots render at the 1280x720 base regardless of fullscreen.

## Layout
```
start_screen.tscn / scripts/StartScreen.gd   title screen (code-built UI + iso backdrop)
main.tscn         / scripts/Main.gd          the whole game (grid, record/replay, render, HUD)
                    scripts/Token.gd          legacy pawn renderer — UNUSED (pawns are vector now)
assets/sprites/*.png(.import)                 Aseprite art: floor_a, floor_b, wall, hazard
```
Main.gd is intentionally single-file. Keep it that way unless asked.

## Core model — "motion record" (do NOT rewrite into real-time)
Turn-based, deterministic **lockstep**. One global tick; every move advances all ghosts one
step. Two states (Mode.PLAY / Mode.RECORD):

- **PLAY** (default): tangible. Walls block your input; stepping onto a hazard (^) kills you
  (_die -> attempt restarts, ghosts kept). This is how you reach the exit.
- **RECORD** (_begin_record, triggered by **holding SPACE**): you snap to the level start,
  intangible — you may step through **walls and over hazards** (only _in_bounds limits you);
  each step appends to current_path. **Releasing SPACE** (_end_record) banks the ghost (if
  current_path.size() > 1) and restarts the attempt.
- A ghost replays path[clamp(tick,0,len-1)] -> it **freezes on its last tile** past its length
  (how it keeps holding a switch). Ghosts are non-colliding and press switches.
- **Determinism:** _begin_record, _end_record, dying, and full reset all _restart_attempt ->
  tick 0, player at start, all ghosts replay from 0. Keep this invariant.
- Exit opens when every switch is occupied by player-or-ghost in the same tick (always open if
  zero switches). Win = PLAY player on the exit while open. Because ghosts freeze on their last
  tile, design levels so the player's path to the exit is at least as long as each ghost's path
  (switches held by arrival — no explicit wait needed).
- The old Phase Exchange controls (F phase / Q cancel / R commit / E swap) and the swap/teleport
  mechanic were **removed** for being unintuitive. There is no swap and no wait.

## Levels (ASCII)
levels in Main.gd: array of {name, hint, rows, vines?, heights?}.
- rows: # wall, . floor, P start, E exit, ^ spike pit (lethal), 1-9 switch.
- vines (optional): [Vector2i] wall cells that get a hanging vine. heights (optional):
  per-cell elevation digit (currently unused — all flat; level_step/max_climb remain).
- Built + verified solvable: 1 **Ghost Walk** (record through a wall to a sealed switch),
  2 **Spike Gauntlet** (ghost holds a switch; find the safe gap across the pit),
  3 **Dual Lock** (two ghosts, two sealed switches), 4 **Triad** (three ghosts/switches).
- Sealed switches force through-walls recording; open switches just need a ghost parked on
  them. Re-verify solvability via the headless harness before committing.

## Rendering
- Tiles are **112x56** (tile_w/tile_h), wall_height 46. _ground ignores height; _surface =
  ground - height*level_step. Window is fullscreen with canvas_items + expand stretch (base
  1280x720) so it fills the monitor and scales up.
- **One painter pass** in _draw(): iterate cells back-to-front by x+y, draw each cell's
  floor/wall, then ANY pawn whose cell has that same x+y (_draw_pawns_at). This is the fix for
  the old overlap bug — a wall with higher x+y correctly occludes a pawn behind it.
- **Pawns are vector** (_draw_pawn): orange stadium body + head + outline + shadow (player);
  purple translucent + ripple ring (ghost); teal C_PHASE_RING while the live player RECORDs.
  Motion = tween on anim_t (0->1) lerping *_pos_from -> *_pos_to via _set_anim + queue_redraw
  (NOT node-position tweens).
- **Background:** radial GradientTexture2D drawn first in _draw. **Vignette:** its own
  CanvasLayer (layer 5), a radial GradientTexture2D TextureRect, under the HUD layer (10).
- _blit returns false if a sprite is missing -> procedural fallback. Switch/exit glows are
  procedural teal on top; open exit adds a light beam. _draw_vine draws per-level vines;
  _draw_paths/_draw_trace draw the dotted purple path (bright = live recording, faint =
  committed ghosts). There is NO procedural wall-top moss (it looked bad — moss is in sprites).
- **HUD** (_build_hud): a fading title card (<roman> + name + hint, fades ~3s via _show_title),
  a small bottom prompt keyed to PLAY/RECORD, a tiny corner status (switches/ghosts), an
  H-toggled help overlay, and the win banner.

## Sprite pipeline (Aseprite MCP)
- Workspace resolves to the **shared prototypes/ dir**, not this project. export_sprite lands
  in C:\Users\himan\prototypes\; mv PNGs into assets/sprites/ and delete the .aseprite sources.
- draw_line is broken (use thin rects). draw_triangle works (spikes). Coords are 0..size-1.
- Active sprites at the 112px tile: floor_a/floor_b 112x76 (anchor 56,38), wall 112x112
  (56,80), hazard 112x76 (56,38). Switch/exit are procedural; player/ghost are vector.
- **Moss must stay subtle:** a few small, MUTED green specks/patches (e.g. #566b3c / #455334),
  not big bright ellipses. The first pass had ugly blobs — keep lichen restrained, low-contrast.

## Controls
Arrows/WASD move - hold SPACE record a ghost (release to bank) - R/T reset - N next (after
solving) - H help - F11 fullscreen - Esc title.

## Tunable @export knobs (on the Main node)
tile_w, tile_h, wall_height, level_step, max_climb, move_time, echo_alpha, phase_alpha.

## Workflow conventions
- **Commit AND push everything as we go.** Trailer: Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
- gh is NOT on the bash PATH; use the **PowerShell** tool (authed as Hkattelu). Push:
  git push origin master (default branch master).
- **Edit guard:** Write/Edit may be blocked by a worktree-isolation guard. Author files via
  **Bash heredocs**, chunked (cat > f then cat >> f, ~50 lines each) — big single heredocs get
  truncated -> confusing "unexpected EOF". (seed is a built-in — name params sd.)
- Commit Godot .import/.uid files; .godot/ is gitignored.
