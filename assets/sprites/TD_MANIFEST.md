# TD_MANIFEST — Top-down asset set

Produced for the top-down redesign (Part 2 of `TOPDOWN_REDESIGN_PLAN.md`). This is the
asset-generation handoff for the renderer agent. All files live in
`C:\Users\himan\prototypes\echo-chamber\assets\sprites\`.

**PixelLab budget:** trial plan. `generations_remaining` went `2 -> 0`
(`generations_used 38 -> 42`, i.e. the successful top-down tileset cost ~4 generations and
pushed slightly past the 40 cap). All character work was FREE (existing assets reused). No
generations were left for decor, so decor + the floor-decal tiles (hazard/plate/doors) are
zero-generation placeholders (see per-file notes). `.import` files are NOT included — the runtime
loads these PNGs via `Image.load_from_file` (per CLAUDE.md), but launch the Godot editor once so
Godot generates `.import`/`.uid` and the assets are usable as normal resources too.

---

## Characters (REUSED — free, no generations spent)

Source: the two pre-existing PixelLab characters in the account
(`bf9803d8 "Echo Player"` = orange adventurer, `2269c36e "translucent glowing"` = purple echo
state, same group). They were generated 8-direction low-top-down; only the iso-diagonal PNGs had
been exported before. I downloaded the **cardinal** rotations (N/E/S/W) that the top-down renderer
needs — they were already sitting in the character asset ungenerated-as-PNG.

| File | Native size | What it is | Draw treatment |
|------|-------------|------------|----------------|
| pl_n.png | 68x68 | orange hooded adventurer, facing up (north) | foot anchor (34,59), scale 1.35 |
| pl_e.png | 68x68 | player facing right (east) | foot anchor (34,60), scale 1.35 |
| pl_s.png | 68x68 | player facing down / idle (south) | foot anchor (34,58), scale 1.35 |
| pl_w.png | 68x68 | player facing left (west) | foot anchor (34,60), scale 1.35 |
| gh_n.png | 68x68 | purple spectral echo, facing up | foot anchor (34,59), scale 1.35 |
| gh_e.png | 68x68 | echo facing right | foot anchor (34,60), scale 1.35 |
| gh_s.png | 68x68 | echo facing down / idle | foot anchor (34,58), scale 1.35 |
| gh_w.png | 68x68 | echo facing left | foot anchor (34,60), scale 1.35 |

- **Use a single uniform anchor `(34,58)` and scale `1.35`** — matches the engine's existing
  `CHAR_ANCHOR`/`CHAR_SCALE`. Per-frame foot varies only 0-2px; negligible.
- Facing suffixes are now **cardinal** (`_n _e _s _w`), per Part 1.4. Idle = `_s`.
- `pl_s.png` and `gh_s.png` were **overwritten** (same character, south rotation) — this is
  correct, they are the same figure the old set used.
- **Ghost extraction note:** the "translucent glowing" state renders the whole 2-figure group
  (orange player + purple echo side by side) in each rotation PNG. I isolated the purple echo by
  color-keying out the orange player and everything left of the echo, then recentered it onto the
  player footprint (center-x 34). Result is a clean single purple figure. A 1px sliver of the
  echo's left outline may be trimmed — invisible in-engine (ghosts render at ~62% alpha, tinted).

## Floor + wall tiles (GENERATED — `create_topdown_tileset`, cost ~4 gens)

Source: one `create_topdown_tileset` job (high top-down, 32px, lower="mossy stone floor with
subtle green moss", upper="grey stone brick wall", transition 0.25). I cropped the pure-corner
tiles out of the 16-tile Wang sheet (pure floor = all-lower tile; pure wall = all-upper tile).
Seamless-tiling square top-down tiles.

| File | Native size | What it is | Draw treatment |
|------|-------------|------------|----------------|
| td_floor_a.png | 32x32 | mossy olive weathered stone floor | stretch to `tile_size` (96) |
| td_floor_b.png | 32x32 | floor variant (floor_a flipped + slightly darker/cooler) | stretch to `tile_size`; alternate per-cell for variety |
| td_wall.png | 32x32 | grey stone-brick wall, flat top-down (no vertical face) | stretch to `tile_size` |

- No seed param on this tool, so exact seed-777 continuity wasn't possible; palette/mood match the
  worn-tower set.
- **Style note:** the floor moss is a touch green/saturated (still speckled patches over stone,
  NOT the old bright-green blobs). If it reads too loud, `modulate` the floor toward muted olive,
  e.g. `Color(0.92, 1.0, 0.86)` or a small desaturate — cheaper than regenerating.

## Floor-decal tiles (PROCEDURAL — PIL, 0 gens; plan says these can stay procedural)

Generation budget was exhausted, and Part 2 explicitly allows switch/exit/hazard to stay
procedural. These are on-palette PIL tiles so the renderer has real `td_` files to wire; the
renderer's own procedural glow/teeth fallbacks remain equally valid if preferred.

| File | Native size | What it is | Draw treatment |
|------|-------------|------------|----------------|
| td_hazard.png | 32x32 | top-down spike pit (dark recess + grey spikes), opaque | stretch to `tile_size`; replaces floor in that cell |
| td_plate.png | 32x32 | subtle teal pressure plate, transparent margin (decal) | stretch to `tile_size`, draw over floor; renderer adds the glow on top |
| td_door_closed.png | 32x32 | sealed barred stone hatch, no glow | stretch to `tile_size`; use when `exit_open == false` |
| td_door_open.png | 32x32 | glowing teal portal (radial glow + bright core + ring) | stretch to `tile_size`; use when `exit_open == true` |

## Decor props (PLACEHOLDER — PIL, 0 gens)

Reduced roster of 5 (mix of accents + small clutter), all genuinely top-down and on-palette. NOTE:
these are simple PIL placeholders, NOT PixelLab art — I had 0 generations left. The existing iso
decor PNGs (crystal/brazier/statue/obelisk/urn/ferns/rubble/mushrooms, all 64x64) were deliberately
NOT reused as `td_` — they have visible isometric pedestals/side-faces and would look wrong flat.
Upgrade these to real PixelLab `create_map_object` top-down props when generation budget returns.

| File | Native size | What it is | Draw treatment |
|------|-------------|------------|----------------|
| td_crystal.png | 32x32 | teal crystal cluster (Portal accent) | center on cell (anchor 16,16 native), transparent margin |
| td_brazier.png | 32x32 | stone fire bowl w/ orange glow (accent) | center on cell |
| td_rubble.png | 32x32 | scatter of grey stones | center on cell |
| td_mushrooms.png | 32x32 | cluster of muted red-brown caps | center on cell |
| td_ferns.png | 32x32 | radiating fern clump (muted olive) | center on cell |

- All have transparent margins and are centered — draw them centered on a floor cell; no overhang,
  so they won't occlude pawns. Keep them on quiet floor cells per the sparse-decor rule.

---

## Skipped / substituted (with reasons)

- **Real PixelLab top-down decor** (`create_map_object`): SKIPPED. 0 generations remaining (trial
  exhausted at 42/40 after the tileset). Substituted 5 PIL placeholders above.
- **Bespoke PixelLab hazard / plate / door objects**: NOT generated (would also need generations).
  Substituted PIL tiles — and the plan says procedural is acceptable for these anyway.
- **Second real floor variant**: `td_floor_b` is derived from `td_floor_a` (flip + tint), not a
  separate generation, for the same budget reason. Reads fine as a variant.
- **`.import`/`.uid` files**: not created (can't run the Godot editor from here — renderer agent
  owns it). Launch the editor once to import.

## Left untouched (as instructed)
- All existing iso PNGs: `floor_a/b`, `wall`, `door_closed/open`, `hazard`, `plate`, the iso
  diagonal character frames `pl_se/sw/ne/nw` + `gh_se/sw/ne/nw`, and all iso decor
  (`crystal/brazier/statue/obelisk/urn/ferns/rubble/mushrooms`, `wall_mossy/wall_cracked`).
  Only `pl_s.png` and `gh_s.png` were overwritten (same character, correct per the task).
