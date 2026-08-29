extends Node
## Persistent background music player. Registered as an Autoload,
## so this node survives scene changes.

@onready var player: AudioStreamPlayer = AudioStreamPlayer.new()

const TRACK: AudioStream = preload("res://assets/Audio/Sketchbook 2025-11-26.ogg")

var muted: bool = false

func _ready() -> void:
	add_child(player)
	player.stream = TRACK
	if player.stream.has_method("set_loop"):
		player.stream.loop = true  # fallback if import setting didn't stick
	player.volume_db = -5.0
	player.play()

func toggle_mute() -> void:
	set_muted(!muted)

func set_muted(value: bool) -> void:
	muted = value
	player.volume_db = -80.0 if muted else -5.0
