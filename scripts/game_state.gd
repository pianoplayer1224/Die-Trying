# game_state.gd — AUTOLOAD. Register in:
# Project Settings > Globals > Autoload, path res://scripts/game_state.gd,
# name "GameState".
#
# All persistent game state lives here so it survives
# change_scene_to_file() (menu <-> game). main.gd owns the RULES,
# this node owns the NUMBERS.

extends Node

var money := 0
var progress := 0
var best_run := 0

var die_level := 0
var speed_level := 0
var money_mult_level := 0
var match_mult_level := 0

var last_roll := 0          # 0 = "no previous roll"
var match_length := 0
var last_earnings := 0

var game_won := false
## Set when the player takes the "Keep Playing?" offer after the win.
## The win stays recorded (game_won), but the rules stop gating on it
## so the run continues forever.
var endless := false

# Lifetime stats (feed the splash label milestones; may later feed a
# stats screen).
var total_rolls := 0
var bust_count := 0
var total_earned := 0
var total_spent := 0
var playtime := 0.0   # seconds in the game scene, stops after the win


## Wipe everything back to a fresh game. Not called anywhere yet —
## wire this to a future "New Game" button (or call it from the win
## screen for a replay option).
func reset() -> void:
	money = 0
	progress = 0
	best_run = 0
	die_level = 0
	speed_level = 0
	money_mult_level = 0
	match_mult_level = 0
	last_roll = 0
	match_length = 0
	last_earnings = 0
	game_won = false
	endless = false
	total_rolls = 0
	bust_count = 0
	total_earned = 0
	total_spent = 0
	playtime = 0.0
