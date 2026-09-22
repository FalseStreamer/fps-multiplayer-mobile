extends Node3D

@export var interact_ray : RayCast3D
@onready var decal = preload("res://scsnes/objects/objects/bullet_decal.tscn")

var bullet_ray
var spawned_rays = {}


func update_ray():
	pass


func _instanciate(weapon_node: Node3D):
	if weapon_node == null:
		print("No raycast in ", weapon_node)
		return
	
	var ray_model = weapon_node.get_node("fire_ray").instantiate()
	
	if spawned_rays.has(weapon_node):
		spawned_rays[weapon_node] = null
	
	spawned_rays[weapon_node] = ray_model


func _get_interact_obj() -> Node3D:
	var obj = interact_ray.get_collider()
	
	if interact_ray == null:
		return
	
	while obj != null:
		if obj is world_weapon:
			return obj
		obj.get_parent()
	
	return


func _get_target_obj() -> Node3D:
	var obj = bullet_ray.get_collider()
	
	if bullet_ray == null:
		return
	
	while obj != null:
		if obj.is_in_group("target"):
			return obj
		else:
			bullet_decal()
	
	return


func bullet_decal() -> void:
	var decal_model = decal.instantiate()
	bullet_ray.get_collider().add_child(decal_model)
	decal_model.global_transform.origin = bullet_ray.get_collision_point()
	decal_model.look_at(bullet_ray.get_collision_point() + bullet_ray.get_collision_normal(), Vector3.UP)
