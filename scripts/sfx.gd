# sfx.gd — AUTOLOAD "Sfx".
# UI click sounds + master switch for ALL sound effects.
#
# All SFX players in the game route to a shared "SFX" audio bus,
# and mute/unmute toggles that bus — so one switch silences the
# click, buy, win, and dice sounds without touching each player.

extends Node

const CLICK_STREAM := preload("res://assets/Audio/click-button.mp3") # <-- adjust path
const BUS_NAME := "SFX"

var muted := false

var _click_player := AudioStreamPlayer.new()


func _ready() -> void:
	# Create the SFX bus at runtime if it doesn't already exist in the
	# bus layout. Doing it in code means no editor setup to forget and
	# nothing to miss in the web export.
	if AudioServer.get_bus_index(BUS_NAME) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_NAME)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")

	_click_player.stream = CLICK_STREAM
	_click_player.bus = BUS_NAME
	add_child(_click_player)


func click() -> void:
	_click_player.play()


func toggle_mute() -> void:
	set_muted(not muted)


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_NAME), muted)
