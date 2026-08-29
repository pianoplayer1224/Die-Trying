extends StaticBody2D

signal roll_done(value: int)

@onready var faces: Node2D = $Faces
@onready var audio_tick: AudioStreamPlayer = $"Audio-tick"
@onready var audio_roll: AudioStreamPlayer = $"Audio-roll"
@onready var audio_bust: AudioStreamPlayer = $"Audio-bust"

@export var roll_duration := 1.5
@export var tick_count := 12
@export var slowdown := 6.0

var isRolling := false
var currentIndex := 0


func _ready() -> void:
	add_to_group("DiceGroup")
	_set_start_face()

	# Route this die's sounds to the shared SFX bus so the options
	# toggle mutes them along with everything else.
	audio_tick.bus = Sfx.BUS_NAME
	audio_roll.bus = Sfx.BUS_NAME
	audio_bust.bus = Sfx.BUS_NAME


func _set_start_face() -> void:
	for face in faces.get_children():
		face.hide()
	faces.get_child(0).show()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT and not isRolling:
		_roll_dice()


func _roll_dice() -> void:
	isRolling = true
	var delays := _build_delays()
	for i in tick_count:
		var newIndex: int = faces.get_children().pick_random().get_index()
		faces.get_child(currentIndex).hide()
		faces.get_child(newIndex).show()
		currentIndex = newIndex
		audio_tick.play()
		await get_tree().create_timer(delays[i]).timeout
	isRolling = false
	if currentIndex == 0:
		audio_bust.play()
	else:
		audio_roll.play()
	roll_done.emit(currentIndex + 1)


func _build_delays() -> Array[float]:
	var weights: Array[float] = []
	var total := 0.0
	for i in tick_count:
		var t := 0.0 if tick_count <= 1 else float(i) / float(tick_count - 1)
		var w := lerpf(1.0, slowdown, t)
		weights.append(w)
		total += w
	var delays: Array[float] = []
	for w in weights:
		delays.append(roll_duration * w / total)
	return delays
