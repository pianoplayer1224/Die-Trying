# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Die Trying" — a 2D incremental/clicker dice game in **Godot 4.7.1** (GDScript, GL Compatibility renderer, 1920x1080 `canvas_items` stretch). Click the die, accumulate progress to `GOAL`, spend money on upgrades. Web is a first-class target.

## Tooling: use the Godot AI MCP

The `godot-ai` MCP server (`addons/godot_ai`, plugin enabled in `project.godot`) is wired to a live editor — prefer it over the CLI for anything interactive:

- `editor_state` — check version / open scene / play state before doing anything else
- `project_run` (`mode: main|current|custom`) and `project_manage(op="stop")` to play/stop
- `logs_read`, `editor_screenshot`, `scene_get_hierarchy`, `node_*`, `script_patch`, `test_run`
- Writes are rejected while the game is playing (`EDITOR_NOT_READY (state=playing)`); stop first. A `game_status.status="break"` means a GDScript parse error froze boot — stop, fix, relaunch.

There is **no `godot` on PATH**. The editor binary lives at `/home/ray/Documents/Godot/Godot_v4.7.1-stable_linux.x86_64`. CLI fallback:

```bash
/home/ray/Documents/Godot/Godot_v4.7.1-stable_linux.x86_64 --path /home/ray/Documents/Godot/die-trying
```

Export presets are `Web`, `Windows Desktop`, `Android`, `Linux`, all writing into `exports/` (gitignored):

```bash
/home/ray/Documents/Godot/Godot_v4.7.1-stable_linux.x86_64 --headless --path /home/ray/Documents/Godot/die-trying --export-release "Web" exports/index.html
```

The `_mcp_game_helper` autoload comes from the addon, not the game. `addons/` and that autoload are dev tooling; the game code must not depend on them.

There is no test suite yet. `test_manage` / `test_run` (addon's `McpTestRunner`) is the path of least resistance if one is added.

## Architecture

### State lives in autoloads, scenes are disposable

Every screen transition is `get_tree().change_scene_to_file(...)`, which destroys the current scene. Anything that must survive a transition is an autoload (`project.godot > [autoload]`):

- **`GameState`** (`scripts/game_state.gd`) — *the numbers*: money, progress, the four upgrade levels, match state, lifetime stats, `game_won`. Plain vars, no logic. `reset()` exists but is only wired to the options screen's reset button.
- **`Sfx`** (`scripts/sfx.gd`) — UI click + the master SFX switch.
- **`MusicPlayer`** (`scripts/music_player.gd`) — looping BGM, muted via `volume_db`, independent of the SFX bus.
- **`Splash`** (`scripts/splash.gd`) — a *scene* autoload (`splash.tscn`, a `CanvasLayer`) so the splash label keeps rotating and stays drawn above opaque scene backgrounds. Reach the label as `Splash.label` (a `SplashLabel`).

`main.gd` owns *the rules*; `GameState` owns *the numbers*. Keep that split — putting derived logic in `GameState` or persistent values in `main.gd` breaks menu round-trips.

Scene flow: `start.tscn` → `main.tscn` / `options.tscn` / `help.tscn`, each returning to `start.tscn`.

### Dice

All seven `scenes/dice_d_*.tscn` share `scripts/dice.gd` (a `StaticBody2D`). A die is a `Faces` node whose children are one `Sprite2D` per face, shown one at a time; **the rolled value is child index + 1**, so `Faces` child order is the die's numbering and face 0 is the `1` (the bust). Rolling animates `tick_count` face swaps with delays interpolated from fast to `slowdown`-slow over `roll_duration`, then emits `roll_done(value)`. That signal is the only coupling between a die and the game rules.

`main.tscn` instances all seven as `Dice d2` … `Dice d20`; `main.gd` finds them by `"Dice " + tier_name` from `DICE_TIERS`, so **renaming a die node or changing a tier name breaks the lookup**. `_set_active_die()` toggles both `visible` and `input_pickable` — hiding a `StaticBody2D` alone does *not* stop mouse picking.

### Rules (`scripts/main.gd`)

Balance lives in four `const` tables (`DICE_TIERS`, `SPEED_LEVELS`, `MONEY_MULT_LEVELS`, `MATCH_MULT_LEVELS`) plus `GOAL` and `BUST_VALUE`. Level indices in `GameState` index straight into these tables, so appending is safe and reordering/removing rows invalidates saved levels. `DICE_TIERS` keeps cost at index 2 (name, faces, cost); the other three tables at index 1 — that asymmetry is why the dice buy/button code is separate from the generic `_buy_from_table` / `_set_table_button` helpers.

In `_apply_roll()` **order matters**: `match_length` is updated (or reset, on a bust) *before* earnings are computed — that is what makes a bust pay out at 1x.

### Audio

The `SFX` bus is created at runtime in `sfx.gd` (`AudioServer.add_bus()`), not in a bus layout resource. Consequently any new `AudioStreamPlayer` for a sound effect must set `player.bus = Sfx.BUS_NAME` **in code** (see `_ready()` in `main.gd` and `dice.gd`) — a bus assigned in the editor would point at a bus that does not exist at load. Muting toggles the bus, so one switch silences clicks, dice, buys and the win sting.

Never play a click through a player owned by a scene you are about to leave; `change_scene_to_file()` frees it mid-sound. Use `Sfx.click()`, and note `start.gd` awaits ~0.15s before `get_tree().quit()` for the same reason.

### Splash label (`scripts/label_splash.gd`)

`SplashLabel` rotates random one-liners and interrupts with milestone messages. Feed it running totals (`on_rolls_changed`, `on_busts_changed`, `on_money_earned_changed`, `on_money_spent_changed`, `on_playtime_changed`) — they early-out unless a threshold was crossed; only the highest newly-crossed threshold in a call is shown, and each fires once ever. `catch_up_silently()` marks already-earned milestones as seen on scene entry. `get_save_data()` / `load_save_data()` are written for a save system that **does not exist yet** — nothing is persisted to disk anywhere in this project today.

## Conventions

- Tabs for indentation; typed GDScript (`:=`, typed params/returns) throughout.
- Many node names contain spaces or hyphens (`Label add money`, `Container upg`, `Audio-buy`), so `@onready` uses quoted `$"..."` paths. Renaming a node in the editor silently breaks these at `_ready()`.
- `snake_case` for functions and most state; some locals in `dice.gd` / `dice_d_20_menu.gd` are `camelCase` (`isRolling`, `currentIndex`) — match the surrounding file.
- `.godot/`, `exports/` and `/android/` are gitignored; `.gitattributes` forces LF.
