extends Control

@onready var button_exit: Button = $"Button exit"
@onready var button_music: Button = $"VBoxContainer/Button music"
@onready var button_sfx: Button = $"VBoxContainer/Button sfx"
@onready var button_debug: Button = $"VBoxContainer/Button debug"
@onready var button_reset: Button = $"VBoxContainer/Button reset"
@onready var audio_money: AudioStreamPlayer = $"Audio-money"


func _ready() -> void:
	_refresh_labels()


func _refresh_labels() -> void:
	button_music.text = "Music: OFF" if MusicPlayer.muted else "Music: ON"
	button_sfx.text = "SFX: OFF" if Sfx.muted else "SFX: ON"


func _on_button_exit_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/start.tscn")


func _on_button_music_pressed() -> void:
	Sfx.click()
	MusicPlayer.toggle_mute()
	_refresh_labels()


func _on_button_sfx_pressed() -> void:
	Sfx.toggle_mute()
	_refresh_labels()
	# Deliberately after the toggle: silent when switching OFF (correct —
	# SFX are off), audible when switching back ON (instant confirmation).
	Sfx.click()

#DEBUG button
var _debug_press_count: int = 0
var _debug_reward_given: bool = false
func _on_button_debug_pressed() -> void:
	Sfx.click()

	if _debug_reward_given:
		return

	_debug_press_count += 1

	if _debug_press_count >= 10:
		audio_money.play()
		GameState.money += 28530
		_debug_reward_given = true


## "Save Options" — the save code screen, which is also where resetting
## the game now lives.
func _on_button_reset_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/save.tscn")
