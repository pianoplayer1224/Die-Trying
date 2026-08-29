extends Control

func _on_button_exit_pressed() -> void:
	Sfx.click()
	get_tree().change_scene_to_file("res://scenes/start.tscn")
