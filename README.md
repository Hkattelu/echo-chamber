# Echo Chamber

A 2D isometric puzzle prototype built in **Godot 4.6** for a game jam.

You record a run of movement, then "bank" it as an **echo** — a translucent clone that
replays your exact actions in lockstep on every future attempt. You can't collide with
echoes, but they *can* stand on pressure plates. The exit portal only opens while **every
plate is held at the same moment**, so the puzzle is to choreograph past versions of
yourself: one echo holds plate A, another holds plate B, and the live you walks to the exit.

## Core mechanic

The game is **turn-based**. Every action (a move or a wait) advances one global *tick*.
Echoes step forward one recorded action per tick, perfectly synchronized with you. When an
echo runs out of recorded actions it freezes on its last tile — which is how it keeps
holding a plate forever. This deterministic, tile-locked model makes echo timing exact and
frustration-free (no real-time recording desync).

## Controls

| Key | Action |
| --- | --- |
| Arrow keys / WASD | Move along the four isometric diagonals (Up = NE, Right = SE, Down = SW, Left = NW) |
| Space | Wait one tick (stay put but advance time) |
| R / Enter | Bank the current run as an echo and restart the attempt |
| Q | Discard the current run and restart (keeps existing echoes) |
| T / Backspace | Reset the whole level (clears all echoes) |
| N | Next level (after solving) |
| Esc | Quit |

## How to solve a level

1. Walk onto a pressure plate and (optionally) `Space` to settle.
2. Press `R` to bank that path — your clone now holds that plate every attempt.
3. Repeat for each plate, banking one echo per plate.
4. On the final run, with all plates held by echoes, walk the live pawn onto the portal.

Each level needs exactly as many echoes as it has plates: **First Echo** (1), **Twin
Pressure** (2), **Triad** (3).

## Project layout

```
echo-chamber/
├── project.godot        # Godot 4.6, GL Compatibility renderer
├── main.tscn            # root scene (Node2D + Main.gd)
├── icon.svg
└── scripts/
    ├── Main.gd          # grid, recording, echo replay, rendering, HUD
    └── Token.gd         # code-drawn pawn for the player and echoes
```

Levels are defined as ASCII maps inside `Main.gd` (`#` wall, `.` floor, `P` start,
`E` exit, `1`-`9` plates) — easy to add more.

## Tuning knobs

Exposed as `@export` on the `Main` node (tweakable live in the Inspector): `tile_w`,
`tile_h`, `wall_height`, `move_time` (slide snappiness), `echo_alpha` (clone transparency).

## Running

Open the project in Godot 4.6 and press **F5**, or run the `main.tscn` scene.

## Status

Early prototype. All art is drawn procedurally in code (no external assets yet).
