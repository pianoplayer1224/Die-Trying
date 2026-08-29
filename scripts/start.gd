extends Control

## Start menu. Clicks are played through the Sfx AUTOLOAD, not a
## local AudioStreamPlayer — a local player is freed along with this
## scene by change_scene_to_file(), which cuts the sound off after
## ~1 frame. (The start button only ever "worked" because main.tscn
## is slow to load, which happened to leave time for the click.)
@onready var button_quit: Button = $"VBoxContainer/Button quit"

func _ready() -> void:
	$INOP.hide()
	$TLOG.hide()
	# Hide the quit button on web exports — get_tree().quit() does
	# nothing in a browser, so the button would be a dead control.
	#shows inop label
	#if true:
	if OS.has_feature("web"):
		$INOP.show()
		$TLOG.show()
		button_quit.disabled = true
		print("web version")


func _on_button_start_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_button_options_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/options.tscn")


func _on_button_help_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/help.tscn")


func _on_button_quit_pressed() -> void:
	Sfx.click()
	# quit() kills the app instantly — even an autoload player gets
	# no time to be heard — so give the click a moment to play.
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()
