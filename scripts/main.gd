extends Control

## Die Trying — main game logic.
## The dice scenes own their animation/RNG and emit roll_done(value).
## PERSISTENT STATE lives in the GameState autoload so it survives
## leaving to the menu; this script owns the rules and the UI.

# =========================================================
# CONFIG — mirrors the Python tables. d1 removed, so d2 is
# level 0 and costs 0 (it's the starting die).
# =========================================================
const DICE_TIERS: Array = [
	# [display name, faces, cost] — node in main.tscn is "Dice " + name
	["d2", 2, 0],
	["d4", 4, 25],
	["d6", 6, 75],
	["d8", 8, 200],
	["d10", 10, 500],
	["d12", 12, 1200],
	["d20", 20, 4000],
]

const SPEED_LEVELS: Array = [
	# [roll_duration in seconds, cost]
	[3.0, 0],
	[2.6, 50],
	[2.2, 100],
	[1.8, 200],
	[1.4, 500],
	[1.0, 1000],
	[0.8, 2000],
	[0.6, 5000],
]

const MONEY_MULT_LEVELS: Array = [
	# [multiplier, cost]
	[1.0, 0],
	[1.25, 40],
	[1.5, 120],
	[2.0, 300],
	[3.0, 800],
	[4.0, 2000],
]

const MATCH_MULT_LEVELS: Array = [
	# [starting multiplier on a double, cost]
	[2.0, 0],
	[2.5, 20],
	[3.0, 50],
	[3.5, 100],
	[4.0, 250],
]

const GOAL := 500
const BUST_VALUE := 1

# =========================================================
# NODES
# =========================================================
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var label_progress: Label = $"Label progress"
@onready var label_money: Label = $"Label money"
@onready var button_upg_dice: Button = $"Container upg/Button upg dice"
@onready var button_upg_speed: Button = $"Container upg/Button upg speed"
@onready var button_upg_money: Button = $"Container upg/Button upg money"
@onready var button_upg_match: Button = $"Container upg/Button upg match"
@onready var label_add_progress: Label = $"Label add progress"
@onready var label_add_money: Label = $"Label add money"
@onready var label_match: Label = $"Label match"
@onready var audio_buy: AudioStreamPlayer = $"Audio-buy"
@onready var sprite_win: Sprite2D = $"Sprite win"
@onready var audio_win: AudioStreamPlayer = $"Audio-win"
# The splash label lives in the "Splash" autoload (a CanvasLayer),
# not in this scene — it persists across menu <-> game transitions.
@onready var splash_label: SplashLabel = Splash.label


var dice_nodes: Array[Node] = []     # index matches GameState.die_level
var _flash_tweens := {}              # Label -> its active fade Tween


# =========================================================
# SETUP
# =========================================================
func _ready() -> void:
	for tier in DICE_TIERS:
		var die := get_node(NodePath("Dice " + tier[0]))
		dice_nodes.append(die)
		die.roll_done.connect(_on_dice_roll_done)

	button_upg_dice.pressed.connect(buy_die_upgrade)
	button_upg_speed.pressed.connect(buy_speed_upgrade)
	button_upg_money.pressed.connect(buy_money_mult_upgrade)
	button_upg_match.pressed.connect(buy_match_mult_upgrade)

	# Drive the bar's range from GOAL so the constant stays the
	# single source of truth (overrides whatever is set in the editor).
	progress_bar.min_value = 0
	progress_bar.max_value = GOAL

	# Feedback labels start hidden — they only appear on rolls.
	label_add_progress.hide()
	label_add_money.hide()
	label_match.hide()

	# Win sprite stays hidden until the goal is reached.
	sprite_win.hide()

	# Route this scene's sound effects to the shared SFX bus so the
	# options toggle mutes them too.
	audio_buy.bus = Sfx.BUS_NAME
	audio_win.bus = Sfx.BUS_NAME

	_set_active_die()
	_update_ui()

	# With the splash label now persistent (Splash autoload), its
	# fired-state survives scene changes on its own, so this catch-up
	# is redundant during normal play — kept because it's harmless and
	# becomes necessary again the moment a save/load system exists.
	splash_label.catch_up_silently({
		"rolls": GameState.total_rolls,
		"busts": GameState.bust_count,
		"earned": GameState.total_earned,
		"spent": GameState.total_spent,
		"playtime": GameState.playtime,
	})

	# Returning to an already-won game: restore the win state
	# (sprite fully grown, die locked) without replaying the sequence.
	if GameState.game_won:
		_lock_input()
		sprite_win.scale = Vector2(2.0, 2.0)
		sprite_win.show()


## Playtime accrues only while in this scene and stops after the win.
func _process(delta: float) -> void:
	if GameState.game_won:
		return
	GameState.playtime += delta
	splash_label.on_playtime_changed(GameState.playtime)


## Show only the current tier's die, hide (and un-pick) the rest,
## and push the current roll speed onto the active die.
func _set_active_die() -> void:
	for i in dice_nodes.size():
		var die = dice_nodes[i]
		var active := (i == GameState.die_level)
		die.visible = active
		# Hiding a StaticBody2D does NOT stop mouse picking —
		# the collision shape is still live, so disable it too:
		die.input_pickable = active
	dice_nodes[GameState.die_level].roll_duration = \
		SPEED_LEVELS[GameState.speed_level][0]


# =========================================================
# CORE LOOP — reacting to a finished roll
# =========================================================
func _on_dice_roll_done(value: int) -> void:
	if GameState.game_won:
		return
	var progress_before := GameState.progress   # to show "-X" on a bust
	var won := _apply_roll(value)

	# Lifetime stats + splash milestones. If several categories cross a
	# threshold on the same roll, the last call here wins the label.
	GameState.total_rolls += 1
	GameState.total_earned += GameState.last_earnings
	if value == BUST_VALUE:
		GameState.bust_count += 1
	splash_label.on_rolls_changed(GameState.total_rolls)
	splash_label.on_money_earned_changed(GameState.total_earned)
	splash_label.on_busts_changed(GameState.bust_count)

	_update_ui()
	_show_roll_feedback(value, progress_before)

	if value == BUST_VALUE:
		pass
		# TODO (UI): bust feedback — flash, shake, "BUST!" popup.
		# (The die scene already plays the bust sound itself.)

	if won:
		GameState.game_won = true
		_lock_input()
		_play_win_sequence()


## Grow the win sprite from nothing to 2x over 3 seconds while the
## win sound plays.
func _play_win_sequence() -> void:
	sprite_win.scale = Vector2.ZERO
	sprite_win.show()
	audio_win.play()
	var tw := create_tween()
	tw.tween_property(sprite_win, "scale", Vector2(2.0, 2.0), 3.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Per-roll transient feedback. Relies on state already updated by
## _apply_roll() (last_earnings, match_length).
func _show_roll_feedback(value: int, progress_before: int) -> void:
	_flash_label(label_add_money, "+$%d" % GameState.last_earnings)

	if value == BUST_VALUE:
		if progress_before > 0:
			_flash_label(label_add_progress, "-%d" % progress_before)
	else:
		_flash_label(label_add_progress, "+%d" % value)

	if GameState.match_length >= 2:
		_flash_label(label_match, "MATCH x%d (x%s $)" % [
			GameState.match_length, String.num(_get_match_multiplier())])
	else:
		# Cut any lingering fade short so a stale "MATCH x3" isn't
		# still on screen during the roll that broke the match.
		label_match.hide()


## Set text, show, then fade out. Kills any fade already running on
## this label so a fast roll speed doesn't hide fresh text early.
func _flash_label(lbl: Label, new_text: String) -> void:
	lbl.text = new_text
	lbl.modulate.a = 1.0
	lbl.show()
	if _flash_tweens.has(lbl) and _flash_tweens[lbl].is_valid():
		_flash_tweens[lbl].kill()
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.hide)
	_flash_tweens[lbl] = tw


## Direct port of the Python apply_roll(). Returns true on win.
## ORDER MATTERS: match_length must be updated BEFORE earnings
## are calculated (and reset before earnings on a bust) — this is
## what makes a bust pay out at 1x match multiplier.
func _apply_roll(value: int) -> bool:
	if value == BUST_VALUE:
		GameState.best_run = max(GameState.best_run, GameState.progress)
		GameState.progress = 0
		GameState.match_length = 0
		GameState.last_roll = 0
		GameState.last_earnings = _calculate_earnings(value)
		GameState.money += GameState.last_earnings
		return false

	if GameState.last_roll == value:
		GameState.match_length += 1
	else:
		GameState.match_length = 1
	GameState.last_roll = value

	GameState.last_earnings = _calculate_earnings(value)
	GameState.money += GameState.last_earnings

	GameState.progress += value
	GameState.best_run = max(GameState.best_run, GameState.progress)

	return GameState.progress >= GOAL


func _get_match_multiplier() -> float:
	if GameState.match_length < 2:
		return 1.0
	var start := 2.0 + 0.5 * GameState.match_mult_level
	var step := 1.0 + 0.5 * GameState.match_mult_level
	return start + step * (GameState.match_length - 2)


func _calculate_earnings(value: int) -> int:
	var money_mult: float = MONEY_MULT_LEVELS[GameState.money_mult_level][0]
	var match_mult := _get_match_multiplier()
	return int(round(value * money_mult * match_mult))


# =========================================================
# UPGRADES
# =========================================================
## Record a purchase for lifetime stats + splash milestones.
func _register_spend(cost: int) -> void:
	GameState.total_spent += cost
	splash_label.on_money_spent_changed(GameState.total_spent)


## Generic buy for the three table-based upgrades.
## Returns the NEW level, or -1 if the buy failed.
func _buy_from_table(current_level: int, table: Array) -> int:
	if current_level + 1 >= table.size():
		return -1
	var cost: int = table[current_level + 1][1]
	if GameState.money < cost:
		return -1
	GameState.money -= cost
	return current_level + 1


func buy_die_upgrade() -> void:
	if GameState.die_level + 1 >= DICE_TIERS.size():
		return
	var cost: int = DICE_TIERS[GameState.die_level + 1][2]
	if GameState.money < cost:
		return
	GameState.money -= cost
	GameState.die_level += 1
	audio_buy.play()
	_register_spend(cost)
	_flash_label(label_add_money, "-$%d" % cost)
	_set_active_die()
	_update_ui()


func buy_speed_upgrade() -> void:
	var money_before := GameState.money
	var new_level := _buy_from_table(GameState.speed_level, SPEED_LEVELS)
	if new_level == -1:
		return
	GameState.speed_level = new_level
	audio_buy.play()
	_register_spend(money_before - GameState.money)
	_flash_label(label_add_money, "-$%d" % (money_before - GameState.money))
	_set_active_die()  # pushes new roll_duration onto the active die
	_update_ui()


func buy_money_mult_upgrade() -> void:
	var money_before := GameState.money
	var new_level := _buy_from_table(GameState.money_mult_level, MONEY_MULT_LEVELS)
	if new_level == -1:
		return
	GameState.money_mult_level = new_level
	audio_buy.play()
	_register_spend(money_before - GameState.money)
	_flash_label(label_add_money, "-$%d" % (money_before - GameState.money))
	_update_ui()


func buy_match_mult_upgrade() -> void:
	var money_before := GameState.money
	var new_level := _buy_from_table(GameState.match_mult_level, MATCH_MULT_LEVELS)
	if new_level == -1:
		return
	GameState.match_mult_level = new_level
	audio_buy.play()
	_register_spend(money_before - GameState.money)
	_flash_label(label_add_money, "-$%d" % (money_before - GameState.money))
	_update_ui()


# =========================================================
# UI
# =========================================================
func _update_ui() -> void:
	label_money.text = "$%d" % GameState.money
	label_progress.text = "%d / %d" % [GameState.progress, GOAL]
	progress_bar.value = GameState.progress
	_update_upgrade_buttons()

	# Later polish ideas: tween progress_bar.value instead of snapping,
	# animated money count-up.


func _update_upgrade_buttons() -> void:
	# Dice table has cost at index 2, the others at index 1,
	# so the dice button is handled separately.
	if GameState.die_level + 1 >= DICE_TIERS.size():
		button_upg_dice.text = "Dice: %s (MAXED)" % DICE_TIERS[GameState.die_level][0]
		button_upg_dice.disabled = true
	else:
		var cost: int = DICE_TIERS[GameState.die_level + 1][2]
		button_upg_dice.text = "Dice: %s ➜ %s  ($%d)" % [
			DICE_TIERS[GameState.die_level][0],
			DICE_TIERS[GameState.die_level + 1][0], cost]
		button_upg_dice.disabled = GameState.money < cost

	_set_table_button(button_upg_speed, "Speed", GameState.speed_level,
		SPEED_LEVELS, func(v): return String.num(v) + "s")
	_set_table_button(button_upg_money, "Money Mult", GameState.money_mult_level,
		MONEY_MULT_LEVELS, func(v): return "x" + String.num(v))
	_set_table_button(button_upg_match, "Match Bonus", GameState.match_mult_level,
		MATCH_MULT_LEVELS, func(v): return "x" + String.num(v))


## Shared button text/disabled logic for the three uniform tables.
## fmt turns a raw table value into display text (e.g. 2.6 -> "2.6s").
func _set_table_button(button: Button, title: String, level: int,
		table: Array, fmt: Callable) -> void:
	if level + 1 >= table.size():
		button.text = "%s: %s (MAXED)" % [title, fmt.call(table[level][0])]
		button.disabled = true
		return
	var cost: int = table[level + 1][1]
	button.text = "%s: %s ➜ %s  ($%d)" % [
		title, fmt.call(table[level][0]), fmt.call(table[level + 1][0]), cost]
	button.disabled = GameState.money < cost


func _lock_input() -> void:
	# Stop the die from being clickable after the win.
	dice_nodes[GameState.die_level].input_pickable = false


#return to menu
func _on_button_exit_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/start.tscn")
