extends Resource
class_name weapon_res

enum weapon_type {ar,sub_machine,shotgun,sniper,pistol}
enum slots {Primary,Secondary,Knife,Nade}

@export_category("Identification")
@export var weapon_name: String
@export var weapon_id: int
@export var type : weapon_type
@export var slot: slots

@export_category("Visuals")
@export var model: PackedScene
@export var reload_ani: String
@export var wea_up: String
@export var wea_down: String
@export var inspect: String
@export var fire: String
@export var is_auto: bool

@export_category("Data")
@export var damage: int
@export var armour_pen: int
@export var fire_rate: float
@export var cost: int
@export var recoil_pattern: PackedScene

@export_category("Ammunition")
@export var max_ammo: int
@export var mag: int
@export var capacity: int
@export var reload_time: float


func get_slot_name() -> String:
	return slots.keys()[slot]
