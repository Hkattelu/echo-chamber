# CLAUDE.md — Echo Chamber

Guidance for working in this repo. Read this first.

## What this is
A 2D **flat top-down puzzle** prototype in **Godot 4.6** (GL Compatibility renderer), built for a
game jam. Worn, overgrown-tower look (Claude Design handoff): mossy olive stone, **Portal
palette** (orange player, translucent purple ghosts, teal switches/exit), heavy vignette,
minimal isolating HUD. Core mechanic is **record then deploy**: hold SPACE to record your walk
as a *relative motion shape* into a reusable clipboard (release banks the shape, NO ghost yet),
then walk anywhere and press **E** to deploy a ghost at your current cell that traces that shape
from there. Stamp the shape from several spots; stack ghosts to hold switches and open the exit.
The same gesture deployed from a different cell lands the ghost somewhere else — that re-anchoring
is the whole game.

The view is a **plain orthogonal grid** (arrows move the player in the matching screen direction).
It used to be isometric; that projection was replaced (it fought readability — several translucent
past-selves are hard to track on a diamond grid). If you find any iso-specific guidance still
lurking anywhere, it is stale — this doc is canonical.
Repo: https://github.com/Hkattelu/echo-chamber (account Hkattelu).

## Status — known-good, ready to build on (last verified 2026-07-02)
Playable end-to-end, **flat top-down**. The **record→deploy split** is the **verified model**
(documented in the Core model section, still canonical): hold SPACE records your walk from your
CURRENT tile (no teleport) as a sequence of *deltas* and **release banks it into a reusable
clipboard (`gesture_deltas`) — it does NOT spawn a ghost** and snaps you back. You then walk
anywhere and press **E (deploy)** to stamp a ghost at your current cell that traces the clipboard
shape from there, freezing on its last delta to hold a switch. Deploying does not consume the
clipboard; re-recording replaces it.

**All 20 levels** (five tiers) load and are **verified solvable** via the committed headless
harness (`_verify.tscn` + `scripts/_verify.gd`) — a 27-case table: 20 winning solutions all reach
`won=true`, plus 7 deliberately-naive cases that assert `won=false` (they prove a level's trap
actually traps). The full run reports `ALL CASES PASSED`. From Tier C onward (levels 10-20) every
level **requires ≥2 structurally different recorded shapes** (level 13 needs 3; level 18 covers 5
switches with exactly 2), and levels 12/15/19/20 make **elevation** load-bearing.

The player and ghosts are **PixelLab character sprites** (orange adventurer / purple spectral echo),
now with **cardinal** facings (`_n/_e/_s/_w`, idle `_s`). Natural next steps when we return:
switch-gated intermediate doors (Part 4 of the redesign plan) and audio for record/deploy/win.

**History note:** the mechanic evolved through two redesigns that both bit the project, so they are
called out to prevent regression. (1) Ghosts used to be **absolute** world cells (`{path,
start_tick}`), gluing each ghost to the exact tiles it was recorded on — flagged as "kind of dumb";
switched to `{anchor, deltas, start_tick}`. (2) That relative model was still a no-op because
record+bank+deploy all happened at the same instant (release SPACE snapped you back to the anchor);
the fix **decoupled** them: `_end_record()` only fills the clipboard; a separate `_deploy()` (key
**E**) spawns the ghost at `player_cell` with `start_tick = tick`. Then the whole renderer went
**iso → flat top-down** (2026-07-02). Simulation was untouched in that conversion — only screen-space
math and draw order changed. If code and this doc ever disagree on the record/deploy model, **this
doc is canonical** — trust it and re-align the code.

## Running / testing
- Main scene is res://start_screen.tscn (title); it changes to res://main.tscn. The window is
  **fullscreen** by default (F11 toggles; Esc on the title quits).
- **Godot MCP**: launch_editor once after adding/changing assets (to import), then run_project
  (optionally scene: res://main.tscn), then get_debug_output. Or F5.
- **Committed headless harness (`_verify`).** To machine-verify every level is solvable, run the
  committed harness — it instances main.tscn, forces `move_time` tiny, and drives a data-driven
  27-case table through the game's OWN public methods, writing per-case results to
  `res://_verify_results.txt` and exiting 0 iff every case matches its `expect_won`:
  ```
  Godot_v4.6-stable_win64_console.exe --headless --path <project> res://_verify.tscn
  ```
  (`<project>` = this repo root. Use the **console** build so stdout/exit code are visible.) Exit 0
  = all pass; read `_verify_results.txt` for per-case detail (won/expect, switches held, final tick,
  and each ghost's timing margin). **This replaces the old throwaway `_shot.tscn` pattern** — don't
  hand-roll a one-off harness; extend the committed one.
- **Step DSL** (one dict per case in `CASES`: `{"level": int, "name": String, "expect_won": bool,
  "steps": [...]}`). Each step is an array whose first element is an opcode:
  - `["rec"]` — begin recording a gesture at the current cell
  - `["mv", dx, dy]` — one move (dx,dy in {-1,0,1}); during RECORD it phases through walls
  - `["mv", dx, dy, n]` — n identical moves
  - `["end"]` — release/bank the recorded gesture into the clipboard (NO ghost)
  - `["dep"]` — deploy a ghost of the banked gesture at the current cell
  - Multi-switch: `["rec"]…["end"]` to bank a shape, then walk + `["dep"]` per switch. A second
    switch that a translated copy can't reach needs its own `["rec"]…["end"]` (a new shape).
  - **Convention:** every new level gets a winning case; if it has a trap (a naive route/anchor/
    order that *looks* right but fails), add a matching `expect_won:false` case that proves the trap.
- **Harness gotchas (still true):** `:=` type-infer fails on values read off the main scene's
  Variant — use plain `var`. Write results to a FILE, not `print()` (the tree quits before stdout
  flushes). `await` a few `process_frame`s between driven actions (moves are tween-gated by `busy`).
  Screenshots/renders happen at the 1280x720 base regardless of fullscreen.

## Layout
```
start_screen.tscn / scripts/StartScreen.gd   title screen (code-built UI + FLAT top-down backdrop;
                                              hero shot uses the pl_s/gh_s idle sprites)
main.tscn         / scripts/Main.gd          the whole game (grid, record/replay, render, HUD)
                    scripts/Token.gd          legacy pawn renderer — UNUSED (pawns are sprites now)
assets/sprites/*.png(.import)                 TOP-DOWN set (used by the game):
                                              td_floor_a, td_floor_b, td_wall  (32px tiles,
                                                stretched to the fitted tile size at draw)
                                              td_hazard, td_plate, td_door_closed, td_door_open
                                                (32px floor decals)
                                              pl_n/e/s/w, gh_n/e/s/w  (68px player / ghost echo,
                                                cardinal facings + idle _s; foot anchor ~(0.5,0.85)
                                                of sprite size, height = char_scale_frac * tile)
                                              td_crystal/td_brazier/td_rubble/td_mushrooms/td_ferns
                                                (32px PLACEHOLDER decor — see Sprite pipeline)
                                              (older iso PNGs — floor_a/b, wall, hazard, plate,
                                               door_*, the pl_/gh_ diagonal frames, and iso decor —
                                               still sit on disk but NO level references them.)
```
Main.gd is intentionally single-file. Keep it that way unless asked.

## Decor system (cosmetic top-down props)
Levels may carry an optional `"decor": [[Vector2i(x,y), "sprite_name"], ...]` list, parsed in
`load_level` into the `decor` dict (cell -> sprite). It is **purely cosmetic** — `_phys_walkable`
never consults it, so decor cannot change solvability. In `_draw()`, a wall cell that names a decor
sprite draws that variant in place of `td_wall`; a floor cell that names one blits it centred at 0.9
of the tile in a late pass — but **never over a switch, exit, or hazard cell** (that pass explicitly
skips `plates`/`exit_cell`/`hazards`), so clarity is preserved where it matters most. Keep decor
**sparse** (3-6 props/level, on quiet cells); density was a real legibility problem before. Any
named sprite that's missing on disk is simply skipped (lazy `_get_tex` caches the miss). The current
5-prop roster (crystal/brazier/rubble/mushrooms/ferns) are placeholders — see Sprite pipeline.

## Core model — "record then deploy" (RECORD banks a reusable clipboard; DEPLOY stamps a ghost. Do NOT rewrite into real-time, do NOT go back to absolute cells, do NOT re-couple record+deploy)
Turn-based **continuous lockstep timeline**. One global tick; **every player action increments it,
including moves made while RECORDING** (it resets only on level load / death / R-T reset, NOT on
banking or deploying a ghost). Two states (Mode.PLAY / Mode.RECORD):

- **PLAY** (default): tangible. Walls block your input; a step that would climb more than `max_climb`
  height bands is blocked; stepping onto a hazard (^) calls _die.
- **RECORD** (_begin_record, **holding SPACE**): recording starts at the player's CURRENT cell
  (rec_anchor = player_cell — NO teleport to the level start, NO tick reset). You phase through
  **walls, over hazards, and up/down any height** (only _in_bounds limits you); each absolute cell
  you step to appends to current_path (absolute — it's only the live trace + the source for deltas).
  **Each recorded step still advances the global tick** — this is load-bearing: whichever gesture you
  bank first gets a head start, which is the entire puzzle of level 20 ("The Tower's Heart").
  **Releasing SPACE** (_end_record) converts current_path into a RELATIVE shape (deltas = each
  recorded cell minus rec_anchor; `deltas[0]` is always `(0,0)`) and stores it in the **clipboard
  `gesture_deltas`** — it does **NOT** append to `echoes` and **does not spawn a ghost**. The player
  snaps back to rec_anchor and returns to PLAY (tick keeps running). Re-recording **replaces** the
  clipboard.
- **DEPLOY** (_deploy, **key E**, only in PLAY with a clipboard banked): appends
  `{anchor = player_cell, deltas = gesture_deltas.duplicate(), start_tick = tick}` to `echoes` —
  i.e. it stamps a ghost AT THE CELL YOU'RE STANDING ON RIGHT NOW that traces the clipboard shape
  from there. Deploying **does not consume** the clipboard, so you can stamp the same shape from as
  many positions as you like. If nothing is recorded yet, it no-ops with a "Nothing recorded"
  message. (deltas is duplicated on deploy so a later re-record can't mutate already-placed ghosts.)
- **Relative replay (unchanged):** a ghost's cell at global tick T is
  `anchor + deltas[clamp(T - start_tick, 0, len-1)]` (see `_echo_pos`). Because `start_tick` is the
  deploy tick and `deltas[0] == (0,0)`, the ghost spawns ON the deploy cell the instant you press E,
  then walks the relative shape forward one step per subsequent player action, then **freezes on its
  last delta** (holds a switch). **Deploy the same shape from a different cell and the whole shape
  shifts** — anchor + deltas, not baked-in world cells. This is the entire point of the mechanic; do
  not regress it to storing absolute `path` and do not re-couple deploy back into _end_record.
- **Elevation & ghosts:** PLAY movement respects `max_climb` (a solid player climbs ≤1 band), RECORD
  phases through any height, and switch occupancy ignores height — so a switch on a ledge the player
  can't climb is reachable by a *ghost* whose path was recorded while phasing. Levels 12/15/19/20 use
  this.
- **Death / reset clears ghosts but KEEPS the clipboard:** _die and _restart_attempt wipe echoes,
  tick→0, player→start (continuous timelines can't be partially rewound) — but `gesture_deltas`
  **survives** (it's a learned tool; less punishing). Only `load_level` clears the clipboard (a fresh
  level forgets your gesture). R/T = full level reload (clears the clipboard).
- Exit opens when every switch is occupied by player-or-ghost in the same tick (always open if zero
  switches). Win = PLAY player on the exit while open. Design tip: after the last deploy the player's
  route to the exit must be long enough for each ghost to reach its switch (a ghost needs
  `deltas.size()-1` ticks after it is deployed). Verify via the headless harness.
- **Readability:** while a clipboard is banked and you're in PLAY, `_draw_paths`/`_draw_deploy_preview`
  draw a faint **deploy preview** — a teal dotted trace of the shape anchored at your current cell
  plus a very translucent ghost silhouette on its resting tile — so you can see where a deploy would
  land before committing. Committed ghosts draw their own faint dotted trail.
- Removed history: the old **absolute-cell** model (`{path, start_tick}`); the old **record==deploy**
  coupling (release SPACE immediately spawned a ghost at rec_anchor); the old Phase Exchange
  (F/Q/R/E + swap); and the old restart-on-bank "all ghosts replay from tick 0" model. There is no
  swap, no wait key, no per-bank restart, **no absolute path**, and **no auto-spawn on record** —
  record banks a shape, E deploys it.

## Levels (ASCII)
`levels` in Main.gd: array of `{name, hint, rows, heights?, decor?}`.
- rows: `#` wall, `.` floor, `P` start, `E` exit, `^` spike pit (lethal), `1-9` switch.
- heights (optional): per-cell elevation digit (`"00200"` etc.) — a real puzzle axis now (see the
  Core model's elevation note). Cells default to height 0 (flat) when no `heights` block is given.
- decor (optional): see the Decor system section.
- (`vines` is still parsed into a `vines` array for backward compat but is **no longer rendered** —
  the iso `_draw_vine` pass was removed. No current level uses it.)
- **20 levels in 5 tiers, all verified solvable** (headless harness, `won=true`; naive traps
  `won=false`):
  - **Tier A — Foundations (1-4):** 1 First Step, 2 Sealed, 3 Spikes, 4 Twice.
  - **Tier B — Combination (5-9):** 5 Chorus, 6 Sealed Gauntlet, 7 The Long Way, 8 Off-Center,
    9 Crossroads, Refined.
  - **Tier C — Multi-shape mastery (10-14):** 10 Two Shapes, 11 Order Matters, 12 The Vault Above,
    13 Three Shapes, 14 The Divide. Each needs ≥2 structurally different banked shapes (13 needs 3);
    12 makes elevation load-bearing.
  - **Tier D — Precision & scale (15-17):** 15 The Ledge Run, 16 Narrow Margins, 17 The Foundry.
  - **Tier E — Capstones (18-20):** 18 The Choir (5 switches, exactly 2 shapes), 19 The Long Climb,
    20 The Tower's Heart (deploy-order finale — recording advances the tick, so bank-order matters).
  - Elevation levels: 12, 15, 19, 20. `ROMAN` covers 20 (`_roman` falls back to `str(n+1)` beyond).
- Sealed switches force through-walls recording; open switches just need a ghost parked on them (you
  can't stand on the switch AND the exit). Multi-switch levels stamp one banked shape from several
  spots *when* a translation reaches every switch; when it can't, bank a second/third distinct shape.
  **Re-verify solvability via `_verify` before committing any level change** — add/adjust the case,
  drive the actual solution, assert `won`, and check each ghost's timing margin isn't negative.

## Rendering
Flat orthogonal top-down. No iso projection, no painter's-sort, no vertical wall faces.
- **Layout:** `tile_size` (export, 96) is the ideal cell edge; `_recompute_layout()` shrinks the
  fitted `_ts` so any `grid_w x grid_h` board fits the 1280x720 base with a ~1-cell margin, and
  centres it in `board_offset`. `_ground(c) = Vector2(c.x, c.y) * _ts + board_offset` is the cell
  centre; `_surface` == `_ground` (elevation does **not** shift screen position — that read as
  "floating" in flat top-down). Window is fullscreen with canvas_items + expand stretch so it scales
  to the monitor. Re-centres on viewport resize.
- **`_draw()` layers, back-to-front (no occlusion to resolve):** (1) radial `bg_tex` +
  `_draw_backdrop()` (a faint square-tile surround fading out around the island — replaces the iso
  diamond tiling); (2) floor tiles row-major (`_draw_floor`: `td_floor_a`/`td_floor_b` checker,
  per-height brightening tint, a thin low-alpha grid line on every edge); (3) `_draw_ledges()` only
  if the level has height (a dark drop-shadow line + lit lip on a raised cell's downhill edges);
  (4) decals (`_draw_decals`: `td_hazard`, `td_plate` + procedural teal glow, `td_door_closed`/
  `td_door_open` by `exit_open`); (5) flat walls (`_draw_wall`: `td_wall`, or a wall-variant decor
  sprite, one tile — no column/face); (6) sparse decor props; (7) ghost trails + deploy preview
  (`_draw_paths`) UNDER pawns so they never hide behind geometry; (8) pawns (`_draw_all_pawns`).
  HUD and vignette are separate CanvasLayers (10 and 5).
- **Elevation display (non-positional):** each height band tints its floor brighter by
  `elev_tint_step` and draws a ledge line on downhill edges — height is read by shade + lip, not by
  lifting the pawn. Flat levels skip both draws (`_max_height == 0`).
- **Pawns are PixelLab character sprites** (`_draw_pawn`): an orange hooded adventurer (player,
  `pl_*`) and a purple spectral echo (`gh_*`), **cardinal** facings — suffix `_n/_e/_s/_w`, idle `_s`
  (facing camera). `player_face` = last move delta; ghosts face the way their shape last walked
  (`_echo_face`). Drawn at `char_scale_frac * _ts` tall with a fractional foot anchor `(0.5, 0.85)`,
  plus a flattened contact shadow and a ghost/phase ring. Ghosts get a subtle **per-deploy-order
  tint** (`GHOST_TINTS`) and, when 2+ ghosts are out, a **tiny numeral badge** so stacked echoes stay
  individually readable. When several pawns share a cell they're **radially staggered** and sorted by
  screen-y. `_draw_pawn_vector` (the old orange stadium body) remains a fallback when a sprite is
  missing. Motion = tween on `anim_t` (0→1) lerping `*_pos_from` → `*_pos_to` via `_set_anim` +
  `queue_redraw` (NOT node-position tweens).
- **Fallbacks:** `_blit_tile` returns false if a sprite is missing → the caller draws a procedural
  fallback (checker floor, spike-teeth pit, teal plate glow, sealed/open door, bevelled wall). So the
  game renders even before assets import.
- **HUD** (`_build_hud`): a fading title card (`<roman> · name` + hint, fades ~3s via `_show_title`),
  a bottom prompt keyed to PLAY/RECORD/gesture-ready, a tiny corner status (switches/ghosts + a
  "gesture ready · E" flag), an H-toggled help overlay, and the win banner.

## Sprite pipeline
- **Top-down set (what the game uses):** `td_floor_a`, `td_floor_b`, `td_wall` are 32px PixelLab
  top-down tiles (`create_topdown_tileset`, mossy stone floor / grey brick wall) cropped from the
  Wang sheet; `td_hazard`, `td_plate`, `td_door_closed`, `td_door_open` are 32px on-palette decals;
  all stretch to the fitted tile at draw. `pl_n/e/s/w` + `gh_n/e/s/w` are the 68px cardinal character
  rotations, **reused free** from the pre-existing PixelLab characters (they were generated 8-dir
  low-top-down; only the iso-diagonal PNGs had been exported before). See `assets/sprites/
  TD_MANIFEST.md` for the full per-file handoff.
- **PixelLab budget is EXHAUSTED** (trial plan hit 0 generations, ~42/40 used after the tileset). So
  the **5 decor props are PIL placeholders** (`td_crystal/td_brazier/td_rubble/td_mushrooms/td_ferns`),
  flagged in `TD_MANIFEST.md` for real `create_map_object` regeneration when budget returns; the
  hazard/plate/door decals are also procedural (the plan allows this). Don't burn generations without
  checking `get_balance` first — and the old iso decor PNGs are **not** reusable top-down (they have
  visible iso pedestals/side-faces).
- **Runtime loads PNGs via `Image.load_from_file`**, so sprites render even without Godot `.import`
  files — but **launch the editor once** after adding a PNG so Godot generates `.import`/`.uid`, and
  **commit those** (`.godot/` stays gitignored).
- **Moss must stay subtle:** a few small, MUTED green specks over stone, never big bright blobs — a
  real problem twice before. Keep any regenerated ground/wall tiles low-contrast muted olive; if
  `td_floor_a`'s moss reads too loud, `modulate` the floor toward olive rather than regenerating.
- **Aseprite MCP** (if used for touch-ups): its workspace resolves to the shared `prototypes/` dir,
  so exports land in `C:\Users\himan\prototypes\` — move PNGs into `assets/sprites/`. `draw_line` is
  broken (use thin rects); `draw_triangle` works.

## Controls
Arrows/WASD move — hold SPACE record a gesture (release to bank a reusable shape, no ghost yet) —
**E deploy** (stamp a ghost of the banked shape at your current cell; stamp from anywhere, repeat
freely) — R/T reset — N next (after solving) — H help — F11 fullscreen — Esc title.

## Tunable @export knobs (on the Main node)
`tile_size` (ideal cell edge; auto-shrinks to fit big boards), `char_scale_frac` (character height as
a multiple of the fitted tile), `elev_tint_step` (per-height-band floor brightening), `max_climb`
(sim: tallest step a solid player may climb), `move_time`, `echo_alpha`, `phase_alpha`.
(The iso `tile_w`/`tile_h`/`wall_height`/`level_step` exports were removed in the top-down conversion.)

## Workflow conventions
- **Commit AND push everything as we go.** Trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
  (use the current agent's model name).
- gh is NOT on the bash PATH; use the **PowerShell** tool (authed as Hkattelu). Push:
  `git push origin master` (default branch master).
- **Edit guard:** Write/Edit may be blocked by a worktree-isolation guard. Author files via **Bash
  heredocs**, chunked (`cat > f` then `cat >> f`, ~50 lines each) — big single heredocs get truncated
  → confusing "unexpected EOF". (`seed` is a built-in — name params `sd`.)
- Commit Godot `.import`/`.uid` files; `.godot/` and `_verify_results.txt` (a regenerated harness
  artifact) are gitignored.
