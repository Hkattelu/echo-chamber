# Echo Chamber

A 2D **top-down temporal-puzzle** prototype built in **Godot 4.6** for a game jam.
Worn overgrown-tower look; a "record then deploy" ghost mechanic.

## The mechanic — record, then deploy

You don't clone yourself on the spot. You **record a walk** into a reusable clipboard, then
**deploy** copies of it wherever you stand:

1. **Hold SPACE to record.** While held you walk *through walls and over spikes* (you're phasing) —
   each step is captured as a **relative shape** (a sequence of deltas), not fixed tiles.
2. **Release SPACE to bank it.** The shape goes into a clipboard and you snap back to where you
   started. **No ghost spawns yet.** Re-recording replaces the clipboard.
3. **Walk anywhere and press E to deploy.** A translucent purple **ghost** appears at your current
   cell and traces the banked shape from there, then freezes on its last step — holding a switch.

Because the shape is *relative to where you deploy it*, the same recorded gesture lands the ghost in
a different place depending on where you stand. **That re-anchoring is the whole game.** Deploying
doesn't consume the clipboard, so you can stamp the same shape from many spots — but some switches
sit where no single shape can reach them all, so you'll bank a second (or third) distinct shape.

The exit portal opens only while **every switch is held at the same moment**. Ghosts are immune to
spikes and can stand on ledges you can't climb — you are not, and you can't be two places at once, so
you choreograph past-selves to hold the switches while the live you walks to the door.

The timeline is **turn-based and deterministic** (every action, including a recorded step, advances
one global tick), so ghost timing is exact — no real-time desync.

## Controls

| Key | Action |
| --- | --- |
| Arrow keys / WASD | Move (up/down/left/right — plain top-down) |
| Hold **Space** | Record a gesture (walk through walls); release to bank it as a reusable shape |
| **E** | Deploy — stamp a ghost of the banked shape at your position (stamp from anywhere, repeat freely) |
| **R / T** | Reset the level |
| **N** | Next level (after solving) |
| **H** | Toggle help |
| **F11** | Toggle fullscreen |
| **Esc** | Back to title |

## Levels

**20 levels across 5 tiers**, escalating from single-switch basics to multi-shape, elevation, and
deploy-order finales:

- **A — Foundations (1-4):** First Step · Sealed · Spikes · Twice
- **B — Combination (5-9):** Chorus · Sealed Gauntlet · The Long Way · Off-Center · Crossroads, Refined
- **C — Multi-shape mastery (10-14):** Two Shapes · Order Matters · The Vault Above · Three Shapes · The Divide
- **D — Precision & scale (15-17):** The Ledge Run · Narrow Margins · The Foundry
- **E — Capstones (18-20):** The Choir · The Long Climb · The Tower's Heart

Levels 10 onward each require at least two structurally different recorded shapes; 12/15/19/20 make
elevation load-bearing (a switch on a ledge you can't climb is reachable only by a phasing ghost).

## Running

Open the project in Godot 4.6 and press **F5** (starts at the title screen, then the game).

## Verifying levels are solvable

Every level ships with a machine-checked solution. The committed headless harness drives each
level's real solution through the game's own methods and asserts the win state (20 winning cases +
7 naive "this trap really traps" cases):

```
Godot_v4.6-stable_win64_console.exe --headless --path . res://_verify.tscn
```

Exit code 0 means all cases passed; per-case detail (win/expect, switches held, timing margins) is
written to `_verify_results.txt`.

## Project layout

```
echo-chamber/
├── project.godot           # Godot 4.6, GL Compatibility renderer
├── start_screen.tscn       # title screen (StartScreen.gd)
├── main.tscn               # the game (Main.gd)
├── _verify.tscn            # headless solvability harness (_verify.gd)
├── assets/sprites/         # top-down tiles, decals, and player/ghost characters
└── scripts/
    ├── Main.gd             # grid, record/deploy, replay, top-down rendering, HUD
    ├── StartScreen.gd      # title screen
    └── _verify.gd          # data-driven 27-case level verifier
```

Levels are ASCII maps inside `Main.gd` (`#` wall, `.` floor, `P` start, `E` exit, `^` spike pit,
`1`-`9` switches; an optional `heights` block gives per-cell elevation) — easy to add more.

## Tuning knobs

Exposed as `@export` on the `Main` node (tweakable live in the Inspector): `tile_size`,
`char_scale_frac`, `elev_tint_step`, `max_climb`, `move_time`, `echo_alpha` (ghost transparency),
`phase_alpha`.

## Status

Playable prototype, top-down. All 20 levels verified solvable via the headless harness. Art is a mix
of PixelLab sprites and procedural fallbacks (a few decor props are placeholders pending art budget).
