# Echo Chamber — Top-Down Redesign & 20-Level Overhaul

**Owner of this initiative:** Claude Fable, running autonomously overnight.
**Written by:** Claude Sonnet 5, from a full read of `scripts/Main.gd` (1055 lines, all of it),
`scripts/StartScreen.gd`, `README.md`, `CLAUDE.md`, the 14 current levels, and the sprite set.

## How to use this document

Work top to bottom. Each numbered task in **Part 5 (Task List)** is scoped to be independently
committable — commit and push after each one, per this repo's own workflow convention. Don't
batch everything into one giant commit at the end; if something goes wrong at 4am, a clean commit
trail is what saves the run.

**This document supersedes `CLAUDE.md`'s isometric-specific instructions** (the "What this is,"
"Rendering," and parts of the "Sprite pipeline" sections describe the *current*, isometric
architecture — that architecture is being replaced). Everything else in `CLAUDE.md` still applies:
the record/deploy mechanic's rules, the workflow conventions (commit-and-push, PowerShell for gh,
the Edit-guard heredoc workaround, Godot/Aseprite/PixelLab MCP usage notes). **The last task in
Part 5 is to rewrite `CLAUDE.md` itself** so it's canonical again once the dust settles — don't
leave it describing a game that no longer exists.

---

## Part 0 — Diagnosis: why the current build feels janky

Grounded in the actual code, not vibes:

1. **The isometric projection actively fights readability.** `_ground()` maps grid cell `(x,y)` to
   screen space via `((x-y)*tile_w/2, (x+y)*tile_h/2)` — a diamond grid. `_draw()` then does a
   back-to-front painter's sort by `x+y` diagonal to get occlusion right (walls in front of pawns
   behind them, etc.). This is the *correct* way to do isometric occlusion, but it means **ghosts,
   the player, walls, and decor all compete for the same visual depth cues**, and a translucent
   purple ghost (`echo_alpha = 0.62`) walking behind a wall corner or stacked near another ghost is
   genuinely hard to parse in motion. This is structural, not a tuning problem — it's why the user
   correctly identifies isometric as the wrong projection *for this specific mechanic*, where the
   whole point is to visually track multiple translucent past-selves at once.

2. **Arrow keys don't map to intuitive directions.** Because of the iso projection, `Up` moves the
   player diagonally on screen (NE), not "up." This is a constant low-grade disorientation tax on
   top of the ghost-tracking problem above.

3. **Every level is the same puzzle wearing a different room.** Read the 14 levels in
   `Main.gd:101-337`: nearly all of them are "record one gesture, deploy it from N symmetric
   spots, walk to the exit." The game's own hint text gives this away — e.g. level 1's hint is
   *"Hold SPACE and walk through the wall onto the switch, release to leave a ghost, then walk to
   the exit"* — which is not a hint, it's the literal solution transcribed. Not one of the 14
   levels requires **two different recorded shapes** in the same level, even though the clipboard
   model (`gesture_deltas` gets *replaced* on re-record, not appended) obviously supports it and
   is the single biggest untapped source of puzzle depth in this design. Not one level uses
   `heights`/`max_climb` (`Main.gd:20-22`, `676`) — a whole climbing/elevation axis sits completely
   unused. Rooms are small, mostly symmetric, and mostly empty — there's nothing to figure out
   spatially, only something to execute.

4. **Decor clutter compounds the legibility problem.** Some 9x8 rooms carry 8-10 decor props
   (`Main.gd:115-121` etc.) crammed into a small space that's already hard to read isometrically.
   Cosmetic density is fighting the puzzle's readability instead of supporting it.

5. **Sprites aren't the core problem, but they're tuned for the wrong camera.** The PixelLab
   character set was generated 8-directional/low-top-down and then *cropped down to 4 iso-diagonal
   facings* (`_se/_sw/_ne/_nw/_s`) for the isometric renderer. A top-down conversion may be able to
   reuse or cheaply re-derive assets rather than starting from zero — see Part 2.

**Conclusion:** the fix is two independent efforts that should both happen: (A) a rendering
conversion to flat top-down for legibility, and (B) a full level-design pass that actually uses the
mechanic's depth (multi-shape sequencing, elevation, decoy geometry, timing) instead of one
formula repeated 14 times. Neither one alone fixes "the game requires zero thinking."

---

## Part 1 — Top-down conversion (architecture spec)

**Good news found while reading the code:** the entire simulation — movement, recording, the
`anchor + deltas[clamp(...)]` ghost replay, switch/exit logic, win checking — operates purely on
`Vector2i` grid cells and never touches screen-space math. `_move`, `_advance`, `_echo_pos`,
`_update_state`, `_check_win` etc. need **zero logic changes**. This is almost entirely a
rendering-layer rewrite. Do not touch simulation code beyond what's listed below.

### 1.1 Coordinate system
Replace the diamond projection with a plain orthogonal grid.
- Replace `tile_w`/`tile_h` (112/56, iso diamond dims) with a single `@export var tile_size: int`
  (recommend **96**, keeping tiles chunky/readable at 1280x720 — 12-13 cells fit comfortably).
- `_ground(c)`: change from `((x-y)*tile_w*0.5, (x+y)*tile_h*0.5) + board_offset` to
  `Vector2(c.x, c.y) * tile_size + board_offset`.
- `board_offset` centering math in `load_level` simplifies to centering a `grid_w x grid_h`
  rectangle in the viewport — no diamond bounding-box math needed.
- **Drop vertical elevation from screen position.** `_surface()` currently lifts pawns up by
  `height*level_step` px for the iso "raised platform" look. In flat top-down that reads as
  floating, not elevated. Reactivating `heights`/`max_climb` as a real puzzle mechanic (see Part 3)
  needs a *non-positional* way to show elevation instead: e.g. a distinct floor-tile tint/border
  per height band, a small elevation pip/number in the corner of the tile, or a drawn "ledge"
  border sprite between adjacent cells of different height. Pick one, keep it consistent, keep it
  subtle — the point is legibility, not decoration.

### 1.2 Rendering pipeline — replace the painter's sort with clean layers
The `x+y`-diagonal interleave in `_draw()` (`Main.gd:875-889`) existed to solve iso occlusion.
Flat top-down has no occlusion ambiguity between floor/wall/pawn — **use simple back-to-front
row-major layers instead**:
1. Background + backdrop (simplified: a flat tiled floor motif fading at the edges, or just a solid
   dark surround — the diamond `_draw_backdrop()` iso tiling goes away entirely).
2. Floor tiles (row by row).
3. Floor decals: hazards, switch plates, exit door — same visual layer as floor, drawn on top of it.
4. Wall tiles (row by row) — **flat blocks, no vertical face/column extrusion.** Delete
   `_draw_column` and the `wall_height` vertical-face drawing in `_draw_wall`. A wall is one tile,
   full stop. (A *subtle* few-px bevel/inset shadow for polish is fine — just make sure no sprite's
   drawn footprint ever bleeds into a neighboring cell in a way that could occlude a pawn there.
   That "sprite taller than its tile" pattern is exactly what made the iso version unreadable.)
5. Decor props (sparse — see 3.4 below).
6. **Ghost trail overlays** (the dotted paths) — draw these *under* the pawns but *above*
   floor/decor so they're always visible, never lost behind a wall corner.
7. Pawns (player + ghosts), simple depth handling: if two pawns share a cell, offset/stagger them
   slightly (small radial jitter) rather than relying on draw order — with several ghosts stackable
   on one switch this will happen often and needs to stay legible.
8. HUD / vignette (unchanged, already a separate CanvasLayer).

This also means `queue_redraw`-driven per-cell functions (`_draw_floor`, `_draw_wall`,
`_draw_pawns_at`) get simpler, not just relocated — no more `s` diagonal-band loop, just two nested
`for y / for x` passes.

### 1.3 Movement mapping (bug-fix, basically free)
`_move`'s deltas (`Vector2i(0,-1)` for Up, etc.) don't change. What changes is that `Up` will now
*visually* move the pawn up the screen instead of diagonally — this alone fixes a chunk of the
"why is this confusing" complaint with zero extra work.

### 1.4 Character facing
Rename the facing-suffix scheme from iso diagonals to cardinal directions:
`_face_suffix()` (`Main.gd:811-816`) currently maps `(1,0)->_se, (0,1)->_sw, (-1,0)->_nw,
(0,-1)->_ne`. Change to the natural top-down mapping: `(1,0)->_e, (0,1)->_s, (-1,0)->_w,
(0,-1)->_n`, idle `_s` (facing camera) as before. `_echo_face()` logic is unchanged (it just feeds
a delta into this function).

### 1.5 Readability features worth adding while you're in here
These directly answer "hard to see what's going on":
- A thin, low-alpha grid line on every floor tile edge. Cheap, and it's the single highest-value
  legibility win for a puzzle game with multiple stacked translucent actors.
- Give deployed ghosts a subtle per-deploy-order visual distinction (slightly different tint step,
  or a tiny numeral badge) so the player can tell "ghost 1" from "ghost 3" at a glance when several
  are on screen — useful once levels start requiring multiple shapes (Part 3, Tier C+).
- Keep the existing deploy-preview dotted trace and ghost-path traces (`_draw_paths`,
  `_draw_deploy_preview`) — they're good ideas, just re-home them to the new coordinate system.
- Keep the phase-ring visual cue for RECORD mode (walking through walls) — it's a good "you are
  currently intangible" signal, doesn't depend on projection.

### 1.6 Title screen
`StartScreen.gd` has its own small iso renderer (`_iso`, `_diamond`, hero-shot tile grid). Convert
it the same way: flat tile grid, cardinal-facing hero shot. Low-risk, low-priority relative to the
main game — do it, but don't let it block level work.

---

## Part 2 — Asset plan (PixelLab)

**Before generating anything, call `get_balance` and check per-tool costs.** `CLAUDE.md` already
flags that some PixelLab generation tools cost 20-40x more than others on a trial plan
(`create_isometric_tile`/`create_map_object` were cheap at 1 gen; the `*_object`/`tiles_pro` family
was expensive). The same caution applies here — confirm costs for `create_topdown_tileset`,
`create_character`, `create_map_object`, and any `*_object` tool before mass-generating, and budget
accordingly (floor + wall + hazard + switch + exit + player + ghost is the *required* set; decor
props are optional polish, see 3.4).

- **Check for reusable character frames first.** `CLAUDE.md`'s sprite-pipeline notes say the
  existing player/ghost characters were generated as **"8-dir, low top-down"** and then only the
  4 diagonal + idle rotations were exported as `pl_*`/`gh_*` PNGs for the iso renderer. Use
  `list_characters` / `get_character` (PixelLab MCP) to check whether the original 8-direction
  character asset still exists in the project — if so, the N/E/S/W rotations you need for top-down
  may already be sitting there ungenerated-as-PNG, saving a full character regeneration. Only
  regenerate from scratch if the original asset is gone or the style needs to change.
- **Tiles:** regenerate floor/wall/hazard as a matched top-down set — `create_topdown_tileset` is
  the purpose-built tool for this (one coherent generation vs. one-off `create_isometric_tile`
  calls). Keep the established palette: mossy olive stone, Portal-esque teal switches/exit, muted
  restrained lichen (the existing "moss must stay subtle" rule in `CLAUDE.md` still applies —
  it was a real problem before, twice).
- **Switch/exit/hazard:** these can stay mostly procedural (as they already are, layered over the
  floor tile) if that's faster than generating bespoke objects — the current procedural glow/pit
  teeth fallbacks already look fine and aren't iso-specific.
- **Decor:** keep the existing worn-tower prop set (crystal, brazier, statue, obelisk, urn, ferns,
  rubble, mushrooms, wall variants) conceptually, but you likely need top-down versions of the ones
  you keep. **Cut the roster down** — density was already a legibility problem (see Part 0.4); you
  don't need to regenerate all 8+ props if 4-5 well-chosen ones cover the new levels' needs.
- **Style continuity:** same seed-777-for-style-match convention the existing sprites used, so the
  new top-down set still reads as the same worn-overgrown-tower world, not a reskin.

---

## Part 3 — Level design system (20 levels)

### Design pillars (apply to every level)
1. **Every level teaches or tests exactly one new idea, or combines 2-3 already-taught ideas in a
   way that isn't a copy-paste of an earlier room.** No two levels should be solved by the same
   mechanical motion at different room sizes.
2. **Hints gesture at the constraint, never transcribe the solution.** Bad (current level 1):
   *"Hold SPACE and walk through the wall onto the switch, release to leave a ghost, then walk to
   the exit."* Good: *"This switch is sealed — walls only let go of you while you're recording."*
   The player should still have to figure out the *sequence*, even after reading the hint.
3. **Decor is a sparse accent, not wallpaper.** 3-6 props per level, never on or adjacent to a
   switch/exit/hazard-boundary tile where clarity matters most.
4. **Verify solvability for real, per the repo's own convention** (see `CLAUDE.md`'s "Running /
   testing" section): build/reuse the `_shot.tscn` + `scripts/_shot.gd` headless harness, drive
   each level's actual solution (`load_level(n)`, `_begin_record()`/`_move()`/`_end_record()` per
   shape, `_move()`+`_deploy()` per switch, walk to exit), assert `main.won == true`, write results
   to a file. **A level that hasn't been driven through the harness and confirmed `won=true` is not
   done, no matter how correct the ASCII map looks.** This bit the project before (it's why the
   record/deploy model went through two redesigns) — don't skip it under time pressure.
5. **Check the timing constraint explicitly, don't eyeball it.** For every switch: the ghost needs
   `deltas.size()-1` ticks after its deploy tick to reach its resting cell. The player's own
   remaining action count (from that deploy to standing on the opened exit) must be `>=` that, for
   every ghost, simultaneously satisfied at the tick the player steps onto the exit. Levels that
   get this wrong are unsolvable, not just easy — the harness run in pillar 4 is what catches it.

### The big untapped lever: multi-shape levels
`gesture_deltas` is a single clipboard that gets *replaced* on every re-record — nothing currently
uses this. From Tier C onward, **require at least two structurally different recorded shapes in
the same level** (switches whose local wall geometry can't be reached by translating one shape).
This is the single highest-value change for making the game feel like a real puzzle game instead of
a "stamp the same shape N times" toy.

### The other untapped lever: elevation
`heights`/`max_climb` (`Main.gd:20-22`) is fully wired up in the simulation and totally unused in
every level. In PLAY mode, `_phys_walkable` blocks a move if the height difference exceeds
`max_climb`; in RECORD mode, height is ignored entirely (you phase through everything but bounds).
That means: a switch on a ledge the player physically can't climb is trivially reachable by a
*ghost*, because the ghost's path was recorded while phasing. Use this from Tier C onward.

### Tier A — Foundations (Levels 1-4)
One new idea per level, generous space, minimal decor. Worked example for level 1:

**Level 1 — "First Step."** A single open switch in a small room, no walls between start/switch/
exit. Teaches: hold-to-record, release-to-bank, walk-to-a-different-spot, press-E-to-deploy, walk
to exit. Hint: *"Record a short walk, then deploy it wherever you like — the ghost repeats your
walk from there."* (Note what this hint does *not* say: it doesn't say "walk onto the switch and
deploy there," forcing the player to realize the ghost needs to *end* on the switch, not the player.)

- **Level 2 — "Sealed."** One switch behind a 1-tile wall gap only reachable by phasing (recording).
  Teaches sealed switches.
- **Level 3 — "Spikes."** A hazard pit blocks the direct path to the exit; ghosts are immune,
  player is not. Teaches hazard immunity asymmetry.
- **Level 4 — "Twice."** Two switches, same shape stamped from two positions (this is the *ceiling*
  of what the current 14 levels ever ask — treat it as the Tier A capstone, not a mid-game beat).

### Tier B — Combination (Levels 5-9)
Combine two Tier-A ideas per level; introduce explicit timing puzzles and the first decoy geometry.
- **Level 5 — "Chorus."** Three sealed switches, one shape stamped three times — raises Level 4's
  stakes with tighter walls.
- **Level 6 — "Sealed Gauntlet."** Sealed switch *and* a hazard pit on the route to it/the exit.
- **Level 7 — "The Long Way."** The exit is close, but the last-deployed ghost needs many ticks to
  reach its switch — the player must deliberately take a longer route to the exit after the last
  deploy. First level where "count the ticks" is the actual puzzle, not incidental.
- **Level 8 — "Off-Center."** The switch's alcove shape looks like it wants a straight-line
  gesture, but the *only* player-reachable anchor cell that lands the ghost correctly is offset by
  one — deploying from the "obvious" spot clips a wall the ghost's path runs through. Teaches: the
  deployed shape is anchor + raw deltas, walls don't block *replay*, so anchor placement is exact,
  not approximate.
- **Level 9 — "Crossroads, Refined."** Capstone: hazard-crossing + sealed switch + a real timing
  margin, in one room.

### Tier C — Multi-shape mastery (Levels 10-14)
First levels that require **re-recording a second, structurally different shape** mid-level.
- **Level 10 — "Two Shapes."** One switch needs an L-turn gesture, a second needs a straight-line
  gesture from a different local geometry — the same shape genuinely cannot solve both.
- **Level 11 — "Order Matters."** A routing/sequencing puzzle: reaching the spot to record the
  second shape requires walking back through a corridor you already used, which only works if the
  first shape's ghosts are already deployed and out of the way conceptually (they don't block
  movement, but the *level geometry* should make backtracking feel earned, not free).
- **Level 12 — "The Vault Above."** First elevation puzzle: a switch sits on a ledge the player
  can't climb (`max_climb` exceeded) but a ghost reaches by phasing there while recording; combine
  with a second, ground-level sealed switch needing a different shape.
- **Level 13 — "Three Shapes."** Capstone: three switches, three distinct shapes, bigger room, one
  hazard pit.
- **Level 14 — "The Divide."** A room that *looks* symmetric (players will instinctively try to
  mirror one shape) but isn't actually solvable that way — breaks the mirroring instinct on
  purpose.

### Tier D — Precision & scale (Levels 15-17)
Bigger, maze-ish, tighter tolerances.
- **Level 15 — "The Ledge Run."** Extended elevation traversal with a hazard moat below — multiple
  height bands, not just two.
- **Level 16 — "Narrow Margins."** A genuinely tight timing puzzle: the naive route to the exit
  arrives *before* the last ghost reaches its switch, forcing a deliberate detour/stall. (If you
  add the optional Wait key from Part 4, this is the level that benefits most — otherwise the
  detour must be geometric, e.g. an oscillation corridor.)
- **Level 17 — "The Foundry."** Larger multi-room layout, 4 switches, 2-3 shapes, deliberately
  non-symmetric, the strongest test yet of "read the room before you record anything."

### Tier E — Capstones (Levels 18-20)
The hardest, most memorable levels — should feel hard-but-fair, not cruel.
- **Level 18 — "The Choir."** 4-5 switches solved by exactly two shapes reused across very
  different local geometries — a thematic capstone: the game's whole thesis is "the same gesture
  means something different depending on where you plant it," so make one level say that outright.
- **Level 19 — "The Long Climb."** Elevation + hazard + multi-shape + real timing margin, largest
  room yet.
- **Level 20 — "The Tower's Heart."** Final capstone. Everything at once: multi-shape, sealed
  switches, hazards, elevation, decoy geometry, and a timing margin that actually requires
  planning the deploy order up front. This is the "you've mastered it" finale — biggest, hardest,
  should take a competent player real thinking time, not reflex.

Don't hand-author all 20 ASCII grids top-down from this doc — the room-shape creativity is exactly
the implementation work being delegated. Use Levels 1 and the "Off-Center"/"Two Shapes" briefs
above as the calibration bar for rigor; every other level brief should hit an equivalent bar.

---

## Part 4 — Optional stretch mechanics (attempt LAST, only after Part 5's required tasks ship)

Do not start these until the required top-down conversion + 20 verified levels are complete,
committed, and pushed. If you run out of night before finishing these, that's fine — the required
scope is a complete, shippable game on its own.

- **Wait key.** There's currently no way to advance a tick without moving (a blocked move is a true
  no-op — `_move` never calls `_advance` if `_phys_walkable` fails) — the only way to "stall" for
  timing puzzles is oscillating between two open tiles. A dedicated wait key removes that awkward
  workaround and makes timing puzzles (Tier B/D above) feel intentional. `Q` is currently unbound
  (freed when the old Phase Exchange mechanic was removed) — good candidate. Implementation: a
  `_wait()` that calls the existing `_advance(player_cell, false)` directly (bypassing `_move`'s
  delta/walkability check, since not-moving is always legal). Small, low-risk, ~5 lines.
- **Switch-gated doors (distinct from the exit).** Right now the *only* thing any switch state
  gates is the exit. Adding an intermediate door tile that opens only while specific switch(es) are
  held would unlock genuine sequence-dependent puzzles ("reach area B only while holding switch A,
  to record a gesture only accessible from there") — the single most valuable depth addition beyond
  what Part 3 already asks for, but it's a real mechanic addition (new `gates` dict, a
  `_phys_walkable` check, load_level parsing, draw logic mirroring the exit door's closed/open
  art) at moderate risk. Only attempt this if the required 20-level baseline is done, verified, and
  pushed first — an incomplete stretch mechanic should never put the shipped baseline at risk.
  Commit the baseline, *then* branch into this if there's time.

---

## Part 5 — Task list

Work in order. Commit and push after each checked-off group (see `CLAUDE.md` workflow
conventions — PowerShell for `gh`, push to `origin master`, `Co-Authored-By: Claude Fable
<noreply@anthropic.com>` trailer). Use the Godot MCP (`launch_editor` after asset changes, then
`run_project` / `get_debug_output`, or F5) and the `_shot.tscn` headless-harness pattern for
verification throughout — don't wait until the end to find out something doesn't run.

**Rendering conversion**
- [ ] Add `tile_size`, remove `tile_w`/`tile_h`/`wall_height`/`level_step` iso-specific exports (or
  repurpose `level_step`/`max_climb` per Part 1.1's elevation-display decision — your call, just
  document the decision inline).
- [ ] Rewrite `_ground`/`_surface`/`board_offset` centering for orthogonal coordinates.
- [ ] Replace the `_draw()` diagonal painter's-sort with layered floor -> decals -> walls -> decor
  -> ghost trails -> pawns passes. Delete `_draw_column`, the iso `_diamond` helper (or repurpose
  for a simple square/rect helper), the vertical wall-face drawing in `_draw_wall`.
- [ ] Delete/replace `_draw_backdrop`'s diamond tiling with a flat equivalent.
- [ ] Rename facing suffixes iso-diagonal -> cardinal (`_face_suffix`, `SPR` keys, sprite filenames).
- [ ] Add the floor grid-line pass and the ghost deploy-order visual distinction (Part 1.5).
- [ ] Convert `StartScreen.gd`'s hero-shot renderer to flat top-down.
- [ ] Sanity-check via `run_project`: confirm the existing 14 levels (unchanged data) still render
  and solve correctly on the new renderer before touching level content — this is your regression
  check that the simulation layer really is untouched.

**Assets**
- [ ] Check PixelLab balance/costs; check for reusable existing character rotations before
  regenerating (Part 2).
- [ ] Generate/derive top-down floor, wall, hazard tiles (`create_topdown_tileset` or equivalent).
- [ ] Generate/derive cardinal player + ghost character sprites (N/E/S/W + idle).
- [ ] Trim and (re)generate a small, deliberately reduced decor prop set.
- [ ] Wire new assets into `SPR`, confirm `_load_textures`/`_blit` still work unmodified (they're
  projection-agnostic).

**Levels**
- [ ] Replace the 14 existing levels with the 20 designed in Part 3, tier by tier. Write hints per
  the "gesture at the constraint, don't transcribe the solution" rule.
- [ ] For every level, verify via the `_shot.tscn` headless harness: drive the actual solution,
  assert `won == true`, and explicitly check the timing margin (pillar 5) for every switch. Delete
  temp harness files after each verification pass per `CLAUDE.md`'s convention (or keep one
  reusable `_shot.gd` you drive per-level with different args — your call).
- [ ] Update `ROMAN` numeral array bound if needed (currently sized for 13; confirm it covers 20 or
  extend it — check `Main.gd:339`, `_roman()` falls back to `str(n+1)` past the array anyway, but
  extending it keeps title-card numerals consistent).

**Stretch (only after the above is fully shipped — see Part 4)**
- [ ] Wait key, if time allows.
- [ ] Switch-gated doors, if time allows.

**Docs**
- [ ] Rewrite `CLAUDE.md`'s "What this is," "Status," "Rendering," and "Sprite pipeline" sections
  to describe the shipped top-down architecture, the final level list/tiers, and any stretch
  mechanics actually implemented. Remove stale isometric-specific guidance rather than leaving it
  alongside the new content.
- [ ] Update `README.md` — it's currently stale even against the *pre-existing* record/deploy model
  (it still describes the old absolute-echo, bank-on-R model from before two redesigns ago). Bring
  it in line with reality: record/deploy, top-down, 20 levels.
- [ ] Final commit + push. Confirm `git status` is clean and `git log` shows a coherent trail of
  incremental commits, not one mega-commit.

---

## Definition of done

- Game launches via `run/main_scene` (`start_screen.tscn` -> `main.tscn`) with no console errors
  (`get_debug_output` clean).
- Rendering is flat top-down: arrow keys move the player in the matching screen direction; no
  diamond/iso projection remains anywhere (main game or title screen).
- All 20 levels are present, each individually verified `won == true` via the headless harness,
  with the timing margin checked, not assumed.
- At least Tier C onward (Levels 10+) demonstrably requires re-recording a second shape — confirm
  this isn't just true "in theory" but is what the verification harness's driven solution actually
  does.
- Decor is sparse and never obscures a switch/exit/hazard boundary.
- `CLAUDE.md` and `README.md` describe the game as it now exists, not as it existed before this
  pass.
- Everything is committed and pushed to `origin master`.

## Appendix — known repo gotchas (carried forward from `CLAUDE.md`, still relevant)

- `gh` is not on the bash PATH — use the **PowerShell** tool for any `gh` calls.
- Aseprite MCP's workspace resolves to the shared `prototypes/` dir, not this project — exported
  PNGs land outside the repo and must be moved into `assets/sprites/`.
- `draw_line` is broken in the Aseprite MCP; use thin rects instead. (Likely moot if you're doing
  tiles via PixelLab, but flagging in case any Aseprite touch-ups happen.)
- Write/Edit may be blocked by a worktree-isolation guard in some execution contexts — if so, author
  files via chunked Bash heredocs (~50 lines at a time; large single heredocs truncate).
- `:=` type inference fails on values read off the main scene's Variant in the headless harness —
  use plain `var`, not `:=`, there.
- The headless harness quits before stdout is flushed reliably — write verification results to a
  file, not `print()`, and read the file back.
- Screenshots/harness renders happen at the 1280x720 base resolution regardless of the window's
  fullscreen setting.
- Moves are tween-gated by `busy` — `await` a few `process_frame`s between driven harness actions.
- Commit Godot `.import`/`.uid` files; `.godot/` stays gitignored.
