# CLAUDE.md — Echo Chamber

Guidance for working in this repo. Read this first.

## What this is
A 2D **isometric puzzle** prototype in **Godot 4.6** (GL Compatibility renderer), built for a
game jam. Worn, overgrown-tower look (Claude Design handoff): mossy olive stone, **Portal
palette** (orange player, translucent purple ghosts, teal switches/exit), heavy vignette,
minimal isolating HUD. Core mechanic is **record then deploy**: hold SPACE to record your walk
as a *relative motion shape* into a reusable clipboard (release banks the shape, NO ghost yet),
then walk anywhere and press **E** to deploy a ghost at your current cell that traces that shape
from there. Stamp the same shape from several spots; stack ghosts to hold switches and open the
exit. The same gesture deployed from a different cell lands the ghost somewhere else — that
re-anchoring is the whole game.
Repo: https://github.com/Hkattelu/echo-chamber (account Hkattelu).

## Status — known-good, ready to build on (last verified 2026-06-15)
Playable end-to-end. The **record→deploy split** is the new **verified model** (documented below):
hold SPACE records your walk from your CURRENT tile (no teleport) as a sequence of *deltas* and
**release banks it into a reusable clipboard (`gesture_deltas`) — it does NOT spawn a ghost** and
snaps you back. You then walk anywhere and press **E (deploy)** to stamp a ghost at your current
cell that traces the clipboard shape from there, freezing on its last delta to hold a switch.
Deploying does not consume the clipboard, so you can stamp the same shape from many spots;
re-recording replaces the clipboard. All **13 levels** load and were **verified solvable** via the
headless harness under this model (each reaches `won=true`) — the multi-switch levels are solved by
stamping ONE recorded shape from several positions. The player and ghosts are now **PixelLab
character sprites** (orange adventurer / purple spectral echo), not vector pawns (see Rendering).
**History note:** the mechanic evolved in two steps. (1) Ghosts used to be **absolute** world cells
(`{path, start_tick}`), gluing each ghost to the exact tiles it was recorded on — flagged as "kind
of dumb"; switched to `{anchor, deltas, start_tick}`. (2) That relative model was still observably
no-op for the player because record+bank+deploy all happened at the same instant (release SPACE
snapped you back to the anchor, so the anchor always equaled where you started recording). The fix
(2026-06-15) **decoupled** them: `_end_record()` only fills the clipboard; a separate `_deploy()`
(key **E**) spawns the ghost at `player_cell` with `start_tick = tick`. Replay is unchanged:
`anchor + deltas[clamp(T - start_tick, 0, len-1)]`. If code and this doc ever disagree on the
record/deploy model, **this doc is canonical** — trust it and re-align the code.
Natural next steps when we return: levels that *require* stamping the same shape from several spots,
a soft "ghost will arrive in N steps" readability cue, and audio for record/deploy/win.

## Running / testing
- Main scene is res://start_screen.tscn (title); it changes to res://main.tscn. The window is
  **fullscreen** by default (F11 toggles; Esc on the title quits).
- **Godot MCP**: launch_editor once after adding/changing assets (to import), then run_project
  (optionally scene: res://main.tscn), then get_debug_output. Or F5.
- **No runtime-screenshot MCP tool.** To eyeball rendering OR machine-verify a level is
  solvable, make a throwaway _shot.tscn + scripts/_shot.gd that instances main.tscn, sets
  main.move_time = 0.0001, and drives the game via its own methods: load_level(n),
  _begin_record(), _move(Vector2i(...)) gesture, _end_record() (banks the clipboard, NO ghost),
  _move(...) to a deploy position, _deploy() (stamps a ghost at player_cell), more _move(...) to
  the exit. Multi-switch levels: record once, then walk + _deploy() per switch (the same shape
  re-anchors at each deploy cell). Await a few
  process_frames between steps (moves are tween-gated by busy). Assert on main.won; write
  results to a FILE (not print — the scene quits before stdout is readable) and/or save_png().
  Run, read, delete temp files. NOTE: := type-infer fails on values read off the main Variant —
  use plain var. Screenshots render at the 1280x720 base regardless of fullscreen.

## Layout
```
start_screen.tscn / scripts/StartScreen.gd   title screen (code-built UI + iso backdrop)
main.tscn         / scripts/Main.gd          the whole game (grid, record/replay, render, HUD)
                    scripts/Token.gd          legacy pawn renderer — UNUSED (pawns are sprites now)
assets/sprites/*.png(.import)                 base Aseprite art: floor_a, floor_b, wall, hazard
                                              + PixelLab iso tiles (64px, blit x1.75): doorway,
                                              plate, wall_mossy, wall_cracked, crystal, brazier,
                                              rubble, mushrooms, statue, obelisk, urn, ferns
                                              + PixelLab characters (68px, x1.35): pl_*/gh_*
                                              (player / ghost echo, _se/_sw/_ne/_nw/_s facings)
```
Main.gd is intentionally single-file. Keep it that way unless asked.

## Decor system (cosmetic iso props — PixelLab MCP sprites)
Levels may carry an optional `"decor": [[Vector2i(x,y), "sprite_name"], ...]` list, parsed in
`load_level` into the `decor` dict (cell -> sprite). It is **purely cosmetic** — `_phys_walkable`
never consults it, so decor cannot change solvability. Tall block props (crystal/brazier/statue/
obelisk + the wall_mossy/wall_cracked variants) go on **wall cells** (`_draw_wall` blits the
variant in place of `wall`); short props (rubble/mushrooms/urn/ferns) go on **quiet floor cells**
(`_draw_floor` blits over the floor) so pawns never overlap them. The **exit** always blits
`doorway` and **switch** cells always blit `plate`, both under their existing procedural glow.
New sprites are PixelLab `create_isometric_tile` (1 generation each, seed 777 for style match);
their SPR entry carries `"anchor": Vector2(32,47)` (the 64px footprint-diamond centre) and
`"scale": 1.75` -> exact 112x56 footprint. `_blit` honours `scale` via draw_texture_rect. Runtime
loads these PNGs through `Image.load_from_file`, so they render even without Godot .import files
(commit the .import files anyway). Regenerate/extend via the PixelLab MCP — avoid the 20-40
generation tools (tiles_pro, *_object) on the trial; isometric_tile/map_object are 1 gen.

## Core model — "record then deploy" (RECORD banks a reusable clipboard; DEPLOY stamps a ghost. Do NOT rewrite into real-time, do NOT go back to absolute cells, do NOT re-couple record+deploy)
Turn-based **continuous lockstep timeline**. One global tick; every player action increments
it (it resets only on level load / death / R-T reset, NOT on banking or deploying a ghost). Two
states (Mode.PLAY / Mode.RECORD):

- **PLAY** (default): tangible. Walls block your input; stepping onto a hazard (^) calls _die.
- **RECORD** (_begin_record, **holding SPACE**): recording starts at the player's CURRENT cell
  (rec_anchor = player_cell — NO teleport to the level start, NO tick reset). You phase through
  **walls and over hazards** (only _in_bounds limits you); each absolute cell you step to appends
  to current_path (current_path stays absolute — it's only the live trace + the source for deltas).
  **Releasing SPACE** (_end_record) converts current_path into a RELATIVE shape (deltas =
  each recorded cell minus rec_anchor; `deltas[0]` is always `(0,0)`) and stores it in the
  **clipboard `gesture_deltas`** — it does **NOT** append to `echoes` and **does not spawn a
  ghost**. The player snaps back to rec_anchor and returns to PLAY (tick keeps running).
  Re-recording **replaces** the clipboard.
- **DEPLOY** (_deploy, **key E**, only in PLAY with a clipboard banked): appends
  `{anchor = player_cell, deltas = gesture_deltas.duplicate(), start_tick = tick}` to `echoes` —
  i.e. it stamps a ghost AT THE CELL YOU'RE STANDING ON RIGHT NOW that traces the clipboard shape
  from there. Deploying **does not consume** the clipboard, so you can stamp the same shape from
  as many positions as you like. If nothing is recorded yet, it no-ops with a "Nothing recorded"
  message. (deltas is duplicated on deploy so a later re-record can't mutate already-placed ghosts.)
- **Relative replay (unchanged):** a ghost's cell at global tick T is
  `anchor + deltas[clamp(T - start_tick, 0, len-1)]` (see `_echo_pos`). Because `start_tick` is the
  deploy tick and `deltas[0] == (0,0)`, the ghost spawns ON the deploy cell the instant you press
  E, then walks the relative shape forward one step per subsequent player action, then **freezes on
  its last delta** (holds a switch). **Deploy the same shape from a different cell and the whole
  shape shifts** — anchor + deltas, not baked-in world cells. This is the entire point of the
  mechanic; do not regress it to storing absolute `path` and do not re-couple deploy back into
  _end_record.
- **Death / reset clears ghosts but KEEPS the clipboard:** _die and _restart_attempt wipe echoes,
  tick→0, player→start (continuous timelines can't be partially rewound) — but `gesture_deltas`
  **survives** (it's a learned tool; less punishing). Only `load_level` clears the clipboard (a
  fresh level forgets your gesture). R/T = full level reload (clears the clipboard).
- Exit opens when every switch is occupied by player-or-ghost in the same tick (always open if
  zero switches). Win = PLAY player on the exit while open. Design tip: the player's path to the
  exit (after the last deploy) must be long enough for the last ghost to reach its switch
  (ghost needs deltas.size()-1 ticks after it is deployed). Verify solvability via the headless harness.
- **Readability:** while a clipboard is banked and you're in PLAY, _draw_paths draws a faint
  **deploy preview** — a teal dotted trace of the shape anchored at your current cell plus a very
  translucent ghost silhouette on its resting tile — so you can see where a deploy would land
  before committing.
- Removed history: the old **absolute-cell** model (`{path, start_tick}`, ghost glued to recorded
  world tiles); the old **record==deploy** coupling (release SPACE immediately spawned a ghost at
  rec_anchor, which made the relative anchor a no-op); the old Phase Exchange (F/Q/R/E + swap); and
  the old restart-on-bank "all ghosts replay from tick 0" model. There is no swap, no wait, no
  per-bank restart, **no absolute path**, and **no auto-spawn on record** — record banks a shape,
  E deploys it.

## Levels (ASCII)
levels in Main.gd: array of {name, hint, rows, vines?, heights?, decor?}.
- rows: # wall, . floor, P start, E exit, ^ spike pit (lethal), 1-9 switch.
- vines (optional): [Vector2i] wall cells that get a hanging vine. decor (optional): see the
  Decor system section. heights (optional): per-cell elevation digit (currently unused — all
  flat; level_step/max_climb remain).
- **13 levels, all verified solvable** (headless harness, won=true): 1 **Ghost Walk**,
  2 **Spike Gauntlet**, 3 **Dual Lock**, 4 **Triad**, 5 **Sentinel** (1 switch, deploy-elsewhere),
  6 **Phase Wall** (sealed switch), 7 **Hazard Hold**, 8 **Twin Pillars** (2 switches, 1 shape),
  9 **Inner Sanctum** (sealed inner room, long reach), 10 **Crossroads** (cross the pit both ways),
  11 **The Moat** (ghost walks across spikes — it's immune), 12 **Triptych** (3 switches, 1 shape),
  13 **The Vault** (3 switches above a pit, exit below).
- Sealed switches force through-walls recording; open switches just need a ghost parked on
  them (still requires a ghost — you can't stand on the switch AND the exit). Multi-switch levels
  are solved by recording ONE shape and stamping it from several deploy positions (one ghost per
  switch — a ghost holds only its final resting cell). **Re-verify solvability via the headless
  harness before committing** — drive each level's solution (R / moves / E / D) and assert won.

## Rendering
- Tiles are **112x56** (tile_w/tile_h), wall_height 46. _ground ignores height; _surface =
  ground - height*level_step. Window is fullscreen with canvas_items + expand stretch (base
  1280x720) so it fills the monitor and scales up.
- **One painter pass** in _draw(): iterate cells back-to-front by x+y, draw each cell's
  floor/wall, then ANY pawn whose cell has that same x+y (_draw_pawns_at). This is the fix for
  the old overlap bug — a wall with higher x+y correctly occludes a pawn behind it.
- **Pawns are PixelLab character sprites** (_draw_pawn): an orange hooded adventurer (player,
  pl_*) and a purple spectral state of the same figure (ghost echo, gh_*), each an 8-direction
  PixelLab character (68px). Only the 4 iso-diagonal facings + idle are used: suffix _se(+x)
  _sw(+y) _nw(-x) _ne(-y) _s(idle). `player_face` = last move delta; ghosts face the way their
  shape last walked (_echo_face). Drawn at CHAR_SCALE (1.35) with foot anchor CHAR_ANCHOR (34,58),
  plus a contact shadow + a ghost/phase ring. _draw_pawn_vector (the old orange stadium body) is
  kept as a fallback when sprites are missing. Motion = tween on anim_t (0->1) lerping
  *_pos_from -> *_pos_to via _set_anim + queue_redraw (NOT node-position tweens). To regenerate the
  character, use PixelLab create_character (8-dir, low top-down) + create_character_state for the
  ghost; save the se/sw/ne/nw/south rotations as pl_*/gh_*.png.
- **Background:** radial GradientTexture2D drawn first in _draw. **Vignette:** its own
  CanvasLayer (layer 5), a radial GradientTexture2D TextureRect, under the HUD layer (10).
- _blit returns false if a sprite is missing -> procedural fallback. Switch/exit glows are
  procedural teal on top; open exit adds a light beam. _draw_vine draws per-level vines;
  _draw_paths/_draw_trace draw the dotted purple path (bright = live recording, faint =
  committed ghosts) and, when a clipboard is banked in PLAY, _draw_deploy_preview draws the teal
  dotted shape + faint ghost silhouette where pressing E would land a ghost. There is NO
  procedural wall-top moss (it looked bad — moss is in sprites).
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
Arrows/WASD move - hold SPACE record a gesture (release to bank a reusable shape, no ghost yet) -
**E deploy** (stamp a ghost of the banked shape at your current cell; stamp from anywhere, repeat
freely) - R/T reset - N next (after solving) - H help - F11 fullscreen - Esc title.

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
