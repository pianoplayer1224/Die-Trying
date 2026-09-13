extends Control

## Save Options. The ten-character save code IS the save system — nothing is
## written to disk. "Label code" always shows the code for the game in
## progress; typing a code in and pressing Load replaces that game.

@onready var label_code: Label = $"Label code"
@onready var line_edit: LineEdit = $LineEdit


func _ready() -> void:
	# Ten characters plus the space of the grouped form on the label, so a
	# code can be typed back exactly as it is shown.
	line_edit.max_length = SaveCode.CODE_LEN + 1
	line_edit.text_submitted.connect(_on_code_submitted)
	_refresh_code()


## The label is rebuilt from GameState, so it is correct on entry and
## after every load and reset.
func _refresh_code() -> void:
	label_code.text = SaveCode.grouped(SaveCode.encode())


## Back to the menu this screen was opened from.
func _on_button_exit_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/options.tscn")


func _on_button_load_pressed() -> void:
	Sfx.click()
	_try_load(line_edit.text)


## Enter in the text field loads too.
func _on_code_submitted(text: String) -> void:
	_try_load(text)


## Feedback goes through the splash label — it is an autoload, so it is
## already on screen here and says what happened for a full interval.
func _try_load(code: String) -> void:
	if SaveCode.load_code(code):
		line_edit.clear()
		_refresh_code()
		Splash.label.show_event("Save code loaded.")
	else:
		Splash.label.show_event("Code not recognised.")


## Wipes the game. The code about to be destroyed goes up in the splash
## label first, so a mis-click can be undone by typing it back in.
func _on_button_reset_pressed() -> void:
	Sfx.click()
	var old_code := SaveCode.grouped(SaveCode.encode())
	GameState.reset()
	_refresh_code()
	Splash.label.show_event("Game reset. Old code: " + old_code)
