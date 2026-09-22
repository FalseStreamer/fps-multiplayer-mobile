extends Control

@onready var base: Sprite2D = $base
@onready var knob: Sprite2D = $"base/knob"

var touch_index := -1
var deadzone: float
var max_dist: float

var output_vec := Vector2.ZERO
var speed := 0.0

func _ready() -> void:
	max_dist = (base.texture.get_size().x * base.scale.x) / 2.0
	deadzone = max_dist / 2.0

func release() -> void:
	knob.position = Vector2.ZERO # Resets knob to local center of base
	touch_index = -1
	output_vec = Vector2.ZERO
	speed = 0.0
	print("joystick release")

func update_joy(touch_pos: Vector2) -> void:
	var center = base.global_position
	var offset = touch_pos - center
	var dist = offset.length()
	print("joystick touched at pos: ", touch_pos)
	
	if dist > max_dist:
		offset = offset.normalized() * max_dist
		dist = max_dist
	
	knob.position = offset
	
	if dist < deadzone:
		output_vec = Vector2.ZERO
		speed = 0.0
	else:
		output_vec = offset.normalized()
		speed = clamp((dist - deadzone) / (max_dist - deadzone), 0.0, 1.0)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if base.global_position.distance_to(event.position) < max_dist:
				touch_index = event.index
				update_joy(event.position)
		elif touch_index == event.index:
			release()
	elif event is InputEventScreenDrag and event.index == touch_index:
		update_joy(event.position)
