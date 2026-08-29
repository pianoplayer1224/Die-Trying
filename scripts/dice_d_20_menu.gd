extends Node2D

@export var tick_interval := 1

@onready var faces: Node2D = $Faces
@onready var timer: Timer = $Timer

var currentIndex := 0

func _ready() -> void:
	_set_start_face()
	timer.wait_time = tick_interval
	timer.timeout.connect(_on_tick)
	timer.start()

func _set_start_face() -> void:
	for face in faces.get_children():
		face.hide()
	faces.get_child(0).show()

func _on_tick() -> void:
	var count := faces.get_child_count()
	if count <= 1:
		return
	var newIndex := currentIndex
	while newIndex == currentIndex:
		newIndex = randi() % count
	faces.get_child(currentIndex).hide()
	faces.get_child(newIndex).show()
	currentIndex = newIndex
