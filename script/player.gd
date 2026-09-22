extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELO := 4.5
const GRAVITY := 9.8
const SHIFT := 3.5
const CROUCH := 2.5

signal hp_update(health, armour, speed)

var direction := Vector2.ZERO
var dir_velo := Vector3.ZERO
var mobile := false
var health := 100
var armour: int = 100
var speed: float = SPEED
var mouse_captured := false
var camera_touch_index := -1

@onready var pivot: Node3D = %pivot
@onready var camera_3d: Camera3D = $pivot/Camera3D
@onready var control_ui: CanvasLayer = %control_ui
@onready var joystick: Control = %joystick

@export var mouse_sensitivity := 0.003
@export var touch_sensitivity := 0.005
@export var interact_ray: RayCast3D
@export var weap_manager: Node3D
@export var util_manager: Node3D


func _ready() -> void:
	if OS.has_feature("windows") or OS.has_feature("macos"):
		set_mobile_mode(false)
	else:
		set_mobile_mode(true)
	
	hp_update.emit(health, armour, speed)

func set_mobile_mode(is_mobile: bool) -> void:
	mobile = is_mobile
	control_ui.visible = mobile
	set_mouse_captured(!mobile)

func set_mouse_captured(captured: bool) -> void:
	mouse_captured = captured
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func crouch() -> void:
	speed = CROUCH

func jump() -> void:
	velocity.y = JUMP_VELO

func rotate_camera(relative_delta: Vector2, sensitivity: float) -> void:
	pivot.rotate_y(-relative_delta.x * sensitivity)
	camera_3d.rotate_x(-relative_delta.y * sensitivity)
	camera_3d.rotation.x = clamp(camera_3d.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseMotion or event is InputEventMouseButton) and mobile:
		set_mobile_mode(false)
	elif (event is InputEventScreenTouch or event is InputEventScreenDrag) and not mobile:
		set_mobile_mode(true)

	if not mobile:
		if event.is_action_pressed("ui_cancel"):
			set_mouse_captured(!mouse_captured)
			return

		if event is InputEventMouseButton and event.pressed and not mouse_captured:
			set_mouse_captured(true)
			return

		if event is InputEventMouseMotion and mouse_captured:
			rotate_camera(event.relative, mouse_sensitivity)

	if mobile:		
		if event is InputEventScreenTouch:
			if event.pressed:
				var joy_pos := joystick.global_position
				var joy_max_dis = joystick.max_dist
				
				if joy_pos.distance_to(event.position) > joy_max_dis and camera_touch_index == -1:
					camera_touch_index = event.index
			else:
				print("Touch release!")
			
		elif event is InputEventScreenDrag and event.index == camera_touch_index:
			rotate_camera(event.relative, touch_sensitivity)
		print("Touch position | ", event.position)

	if event.is_action_pressed("jump") and is_on_floor():
		jump()
	
	if event.is_action_pressed("crouch"):
		crouch()
	elif event.is_action_released("crouch"):
		speed = SPEED
	
	if event.is_action_pressed("shift"):
		speed = SHIFT
	elif event.is_action_released("shift"):
		speed = SPEED
	
	if event.is_action_pressed("interact"):
		pickup()
	
	hp_update.emit(health, armour, speed)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	if mobile and joystick:
		direction = joystick.output_vec
		if direction != Vector2.ZERO:
			if joystick.speed < 0.99:
				speed = SHIFT
			else:
				speed = SPEED
	else:
		direction = Input.get_vector("walk_left", "walk_right", "walk_front", "walk_back")
	
	if direction != Vector2.ZERO:
		dir_velo = (pivot.global_transform.basis * Vector3(direction.x, 0, direction.y)).normalized()
	else:
		dir_velo = Vector3.ZERO

	var weight: float = 15.0 * delta if is_on_floor() else 3.0 * delta
		
	velocity.x = lerp(velocity.x, dir_velo.x * speed, weight)
	velocity.z = lerp(velocity.z, dir_velo.z * speed, weight)
	
	move_and_slide()

func damage(amount: int) -> void:
	health -= amount
	hp_update.emit(health, armour, speed)
	print("Hit! Damage: ", amount, " Health: ", health)
	
	if health <= 0:
		print("You died!")


func pickup() -> void:
	if interact_ray == null:
		printerr("interact_ray is not assigned in the inspector!")
		return
		
	if not interact_ray.is_colliding():
		print("Nothing to pick up")
		return
		
	var target = interact_ray.get_collider()
	
	# Execute pickup logic on target
	if target:
		while target != null:
			if target.has_method("pickup"):
				var item_data = target.pickup() # Returns dictionary with item details and triggers queue_free()
				_route_pickup_data(item_data)
				break
			target = target.get_parent()


func _route_pickup_data(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return
	
	if item_data.is_gun:
		weap_manager.pickup(item_data)
	else:
		util_manager.pickup(item_data)
