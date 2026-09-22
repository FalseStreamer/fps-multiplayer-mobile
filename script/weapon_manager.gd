class_name WeaponManager
extends Node3D

@onready var raycast_holder: Node3D = %raycast_holder

# Weapon dictionary for slots
@export var weapons: Dictionary[weapon_res.slots, weapon_res] = {
	weapon_res.slots.Primary: null,
	weapon_res.slots.Secondary: null,
	weapon_res.slots.Knife: null
}
@export var holder: Node3D
@export var inter_ray: RayCast3D
@export var bullet_ray: RayCast3D

@export_group("Match Settings")
@export var is_ranked_match: bool = false
@export var friendly_fire_enabled: bool = true # Master toggle for friendly fire in ranked

@export_group("Wallbang Settings")
@export var wallbang_enabled: bool = true
@export var max_wall_thickness: float = 0.5 # Maximum wall thickness bullet can pierce (in meters)
@export var max_wallbang_distance: float = 20.0 # Max distance bullet travels AFTER exiting thick walls

var active_slot: weapon_res.slots
# Tracks current ammo loaded in clip per slot enum
var ammo_track: Dictionary[weapon_res.slots, int] = {}
# Tracks reserve ammo available per slot enum
var reserve_track: Dictionary[weapon_res.slots, int] = {}
# Stores instantiated viewmodels per slot enum
var spawn_weapons: Dictionary[weapon_res.slots, Node3D] = {}

var active_model: Node3D
var is_reloading: bool = false
var next_can_fire_time: float = 0.0
var anim_player: AnimationPlayer 

signal damage(amount: int, is_headshot: bool)
signal ammo_updated(current_ammo: int, reserve_ammo: int)


func _ready() -> void:
	for slot_enum in weapons.keys():
		var weapon_data: weapon_res = weapons[slot_enum]
		if weapon_data != null:
			_instantiate_weapon_model(slot_enum, weapon_data)
			ammo_track[slot_enum] = weapon_data.capacity
			var max_res = weapon_data.get("max_reserve") if "max_reserve" in weapon_data else weapon_data.capacity * 3
			reserve_track[slot_enum] = max_res
		else:
			ammo_track[slot_enum] = 0
			reserve_track[slot_enum] = 0

	change_slot(weapon_res.slots.Knife)


func _process(_delta: float) -> void:
	# Continuous auto-firing
	if Input.is_action_pressed("shoot"):
		var current_weapon: weapon_res = weapons.get(active_slot)
		if current_weapon != null and current_weapon.get("is_auto"):
			fire()


func _unhandled_input(event: InputEvent) -> void:
	# Semi-auto firing on press
	if event.is_action_pressed("shoot"):
		var current_weapon: weapon_res = weapons.get(active_slot)
		if current_weapon != null and not current_weapon.get("is_auto"):
			fire()

	if event.is_action_pressed("weapon_change1"):
		change_slot(weapon_res.slots.Primary)
	
	if event.is_action_pressed("weapon_change2"):
		change_slot(weapon_res.slots.Secondary)
	
	if event.is_action_pressed("weapon_change3"):
		change_slot(weapon_res.slots.Knife)
	
	if Input.is_action_just_pressed("drop"):
		drop_weapon(active_slot)
		
	if Input.is_action_just_pressed("reload"):
		reload()
		
	# Interact with world items (pick up weapons)
	if Input.is_action_just_pressed("interact"):
		_try_pickup_world_weapon()


func change_slot(new_slot: weapon_res.slots) -> void:
	if active_slot == new_slot or weapons[new_slot] == null:
		return
	
	if not weapons.has(new_slot):
		print("Slot does not exist in manager: ", new_slot)
		return
	
	#hide the current weapon for the new weapon
	if spawn_weapons.has(active_slot) and spawn_weapons[active_slot] != null:
		play_ani("weapon down")
		spawn_weapons[active_slot].hide()
	
	active_slot = new_slot
	
	# set visibility of the new weapon to true
	if spawn_weapons.has(active_slot) and spawn_weapons[active_slot] != null:
		spawn_weapons[active_slot].show()
		var slot_name: String = weapon_res.slots.keys()[active_slot]
		print("Switched to ", slot_name, " | Ammo: ", ammo_track[active_slot], "/", reserve_track[active_slot])
		
		active_model = spawn_weapons.get(active_slot)
		anim_player = active_model.find_child("AnimationPlayer", true, false)
		
		var b_ray: RayCast3D = active_model.find_child("RayCast3D", true, false)
		
		if not active_model or not b_ray:
			printerr("No raycast in current model")
			return
		
		bullet_ray = b_ray
		
		_notify_ammo_ui()
		play_ani("weapon up")


# Called directly or when picking up a weapon from the world
func switch_weapon(new_weapon: weapon_res, custom_clip: int = -1, custom_reserve: int = -1) -> void:
	if new_weapon == null:
		return
	
	var target_slot: weapon_res.slots = new_weapon.slot

	if not weapons.has(target_slot):
		print("Invalid weapon slot for manager: ", target_slot)
		return

	# Drop currently equipped weapon in that slot first
	if weapons[target_slot] != null:
		drop_weapon(target_slot)

	# Assign new weapon data
	weapons[target_slot] = new_weapon
	
	# Apply custom ammo counts if picked up from world, otherwise default to full
	ammo_track[target_slot] = custom_clip if custom_clip >= 0 else new_weapon.capacity
	
	var default_res = new_weapon.get("max_reserve") if "max_reserve" in new_weapon else new_weapon.capacity * 3
	reserve_track[target_slot] = custom_reserve if custom_reserve >= 0 else default_res
	
	_instantiate_weapon_model(target_slot, new_weapon)
	
	# Auto-equip if we picked up into active slot or currently holding knife
	if active_slot == target_slot or active_slot == weapon_res.slots.Knife:
		change_slot(target_slot)
	
	active_model = spawn_weapons.get(active_slot)
	anim_player = active_model.find_child("AnimationPlayer", true, false)
	
	_notify_ammo_ui()


func drop_weapon(slot_enum: weapon_res.slots) -> void:
	if not weapons.has(slot_enum) or weapons[slot_enum] == null:
		return

	# Remove visual model from holder
	if spawn_weapons.has(slot_enum) and spawn_weapons[slot_enum] != null:
		spawn_weapons[slot_enum].queue_free()
		spawn_weapons.erase(slot_enum)

	weapons[slot_enum] = null
	ammo_track[slot_enum] = 0
	reserve_track[slot_enum] = 0
	
	var slot_name: String = weapon_res.slots.keys()[slot_enum]
	print("Dropped weapon from slot: ", slot_name)
	
	if active_slot == slot_enum:
		for weapon in weapons:
			if weapons[weapon] != null:
				change_slot(weapon)


func _try_pickup_world_weapon() -> void:
	if inter_ray == null or not inter_ray.is_colliding():
		return
		
	var target = inter_ray.get_collider()
	
	if target.has_method("pickup"):
		var pickup_data = target.pickup() # Returns dictionary or weapon resource
		if pickup_data is weapon_res:
			switch_weapon(pickup_data)
		elif pickup_data is Dictionary:
			switch_weapon(pickup_data.resource, pickup_data.get("clip", -1), pickup_data.get("reserve", -1))


func fire() -> void:
	if is_reloading or weapons[active_slot] == null:
		return
	
	# If playing an animation, check if it can be interrupted
	if anim_player and anim_player.is_playing():
		var current_weapon: weapon_res = weapons[active_slot]
		var current_priority = _get_anim_priority(anim_player.current_animation, current_weapon)
		
		# Block firing only if playing equal/higher priority actions (fire, reload, or weapon switch)
		if current_priority >= 2:
			return
	
	if active_slot != weapon_res.slots.Knife and ammo_track[active_slot] <= 0:
		reload()
		return

	if active_slot != weapon_res.slots.Knife:
		ammo_track[active_slot] -= 1
		_notify_ammo_ui()
	print("is colliding with: ", bullet_ray.get_collider())
	play_ani("fire")
	_perform_hit_check()
	


func reload() -> void:
	if is_reloading or not weapons.has(active_slot) or weapons[active_slot] == null:
		return
		
	if active_slot == weapon_res.slots.Knife:
		return
		
	var current_weapon: weapon_res = weapons[active_slot]
	var current_clip: int = ammo_track[active_slot]
	var reserve: int = reserve_track[active_slot]
	
	if current_clip >= current_weapon.capacity or reserve <= 0:
		return

	is_reloading = true
	play_ani("reload")
	
	var ammo_needed: int = current_weapon.capacity - current_clip
	var ammo_to_add: int = min(ammo_needed, reserve)
	
	ammo_track[active_slot] += ammo_to_add
	reserve_track[active_slot] -= ammo_to_add
	
	is_reloading = false
	_notify_ammo_ui()


func _perform_hit_check() -> void:
	if not bullet_ray.is_colliding():
		print("nothing")
		return

	var first_collider = bullet_ray.get_collider()
	var hit_pos = bullet_ray.get_collision_point()
	var ray_dir = -bullet_ray.global_transform.basis.z.normalized()
	var base_dmg = weapons[active_slot].damage

	# 1. Direct Hit
	if _is_valid_target(first_collider):
		var actual_target = _get_damage_target(first_collider)
		_apply_damage(actual_target, base_dmg, false)
		return
	
	# 2. Wallbang Check
	if not wallbang_enabled or not _is_wallbangable(first_collider):
		return

	# 3. Calculate Wall Thickness
	var space_state = get_world_3d().direct_space_state
	var test_start = hit_pos + (ray_dir * max_wall_thickness)
	
	var back_query = PhysicsRayQueryParameters3D.create(test_start, hit_pos)
	back_query.collide_with_bodies = true
	var back_hit = space_state.intersect_ray(back_query)

	if back_hit:
		var exit_pos = back_hit.position
		var wall_thickness = hit_pos.distance_to(exit_pos)

		if wall_thickness <= max_wall_thickness:
			var thickness_ratio = wall_thickness / max_wall_thickness
			var remaining_travel_dist = lerp(max_wallbang_distance, 2.0, thickness_ratio)

			var exit_query = PhysicsRayQueryParameters3D.create(exit_pos, exit_pos + (ray_dir * remaining_travel_dist))
			exit_query.collide_with_bodies = true
			var pen_hit = space_state.intersect_ray(exit_query)

			if pen_hit and _is_valid_target(pen_hit.collider):
				_apply_damage(pen_hit.collider, base_dmg, true)


func _apply_damage(target: Object, base_amount: int, is_wallbang: bool) -> void:
	var final_damage: float = float(base_amount)
	var is_headshot: bool = false
	var is_teammate: bool = target.is_in_group("friendly") or target.is_in_group("team")

	# Block friendly fire in non-ranked matches
	if is_teammate and not (is_ranked_match and friendly_fire_enabled):
		return

	# 1. Apply Wallbang Penalty (30% reduction -> 70% damage remaining)
	if is_wallbang:
		final_damage *= 0.7

	# 2. Apply Friendly Fire Penalty (40% reduction -> 60% damage remaining)
	if is_teammate and is_ranked_match:
		final_damage *= 0.6

	# 3. Apply Headshot Multiplier
	if target.is_in_group("head") or target.name.to_lower().contains("head"):
		is_headshot = true
		final_damage *= 2.0

	var dmg_int = int(final_damage)

	if target.has_method("take_damage"):
		target.take_damage(dmg_int, is_headshot)
	
	emit_signal("damage", dmg_int, is_headshot)


func _get_damage_target(node: Node) -> Node:
	var curr = node
	while curr != null:
		if curr.has_method("take_damage") or curr.is_in_group("enemy") or curr.is_in_group("friendly") or curr.is_in_group("team"):
			return curr
		curr = curr.get_parent()
	return node


func _is_valid_target(obj: Object) -> bool:
	if not (obj is Node):
		return false
		
	var target = _get_damage_target(obj)
	
	if target.is_in_group("enemy") or _is_enemy_hitbox(target) or target.has_method("take_damage"):
		return true
	
	if is_ranked_match and friendly_fire_enabled and (target.is_in_group("friendly") or target.is_in_group("team")):
		return true
		
	return false


func _is_wallbangable(obj: Object) -> bool:
	if obj.is_in_group("wallbangable"):
		return true
	if obj.has_meta("is_wallbangable") and obj.get_meta("is_wallbangable") == true:
		return true
	return false


func _is_enemy_hitbox(obj: Object) -> bool:
	return obj.is_in_group("enemy") or obj.is_in_group("head") or obj.is_in_group("body")


func play_ani(ani_type: String) -> void:
	if active_model == null or anim_player == null:
		return

	var current_weapon: weapon_res = weapons.get(active_slot)
	if current_weapon == null:
		return

	var anim_to_play: String = ""
	var requested_priority: int = 0

	match ani_type:
		"inspect":
			anim_to_play = current_weapon.get("inspect")
			requested_priority = 0
		"weapon up":
			anim_to_play = current_weapon.get("wea_up")
			requested_priority = 1
		"weapon down":
			anim_to_play = current_weapon.get("wea_down")
			requested_priority = 1
		"fire":
			anim_to_play = current_weapon.get("fire")
			requested_priority = 2
		"reload":
			anim_to_play = current_weapon.get("reload_ani")
			requested_priority = 3
	
	if anim_to_play.is_empty() or not anim_player.has_animation(anim_to_play):
		return

	# If an animation is currently playing, check if we can interrupt it
	if anim_player.is_playing():
		var current_anim_name: String = anim_player.current_animation
		var current_priority: int = _get_anim_priority(current_anim_name, current_weapon)
	
		# Block if requested animation has LOWER or EQUAL priority (e.g. fire cannot interrupt reload)
		if requested_priority <= current_priority:
			return
		
		# Interrupt ongoing lower-priority animation immediately
		anim_player.stop()
	
	anim_player.play(anim_to_play)


func _get_anim_priority(anim_name: String, weapon: weapon_res) -> int:
	if anim_name == weapon.get("reload_ani"):
		return 3
	elif anim_name == weapon.get("fire"):
		return 2
	elif anim_name == weapon.get("wea_up") or anim_name == weapon.get("wea_down"):
		return 1
	elif anim_name == weapon.get("inspect"):
		return 0
	return 0


func _instantiate_weapon_model(slot_enum: weapon_res.slots, weapon_data: weapon_res) -> void:
	if weapon_data.model != null and holder != null:
		var model_instance: Node3D = weapon_data.model.instantiate()
		holder.add_child(model_instance)
		model_instance.hide()
		raycast_holder._instanciate(model_instance)
		spawn_weapons[slot_enum] = model_instance
		play_ani("weapon up")


func _notify_ammo_ui() -> void:
	var current: int = ammo_track.get(active_slot, 0)
	var reserve: int = reserve_track.get(active_slot, 0)
	emit_signal("ammo_updated", current, reserve)


func add_reserve_ammo(slot_enum: weapon_res.slots, amount: int) -> void:
	if reserve_track.has(slot_enum):
		reserve_track[slot_enum] += amount
		if slot_enum == active_slot:
			_notify_ammo_ui()
