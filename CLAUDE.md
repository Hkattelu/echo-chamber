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

## Core model — "motion record" (relative replay; do NOT rewrite into real-time)
Turn-based **continuous lockstep timeline**. One global tick; every player action increments
it (it resets only on level load / death / R-T reset, NOT on banking a ghost). Two states
(Mode.PLAY / Mode.RECORD):

- **PLAY** (default): tangible. Walls block your input; stepping onto a hazard (^) calls _die.
- **RECORD** (_begin_record, **holding SPACE**): recording starts at the player's CURRENT cell
  (rec_anchor = player_cell — NO teleport to the level start, NO tick reset). You phase through
  **walls and over hazards** (only _in_bounds limits you); each absolute cell appends to
  current_path. **Releasing SPACE** (_end_record) banks the ghost as
  {path = recorded cells, start_tick = current tick}, snaps the player back to rec_anchor, and
  returns to PLAY (tick keeps running).
- **Relative replay (the key behavior):** a ghost's cell at global tick T is
  path[clamp(T - start_tick, 0, len-1)]. Because start_tick = the bank tick, the ghost spawns at
  path[0] (= rec_anchor = the player's position when they recorded) and walks its path forward
  one step per subsequent player action, then **freezes on its last tile** (holds a switch).
  So a ghost "replays from the player's current position," not from a fixed level-start. (See
  `_echo_pos`.) Record the same moves from a different spot and the ghost lands elsewhere.
- **Death / reset clears ghosts:** _die and _restart_attempt wipe echoes, tick→0, player→start
  (continuous timelines can't be partially rewound). R/T = full level reload. This is harsher
  than the old keep-ghosts-on-death; revisit if it annoys.
- Exit opens when every switch is occupied by player-or-ghost in the same tick (always open if
  zero switches). Win = PLAY player on the exit while open. Design tip: the player's path to the
  exit (after the last record) must be long enough for the last ghost to reach its switch
  (ghost needs len-1 ticks after its bank). Verify solvability via the headless harness.
- The old Phase Exchange (F/Q/R/E + swap) AND the old restart-on-bank "all ghosts replay from
  tick 0" model were **removed**. There is no swap, no wait, no per-bank restart.

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
