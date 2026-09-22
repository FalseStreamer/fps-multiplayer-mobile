extends Label


var value := "Health: %d\nArmour: %d\nspeed: %f"

func mod_hp_ar(hp: int, arm: int, speed: float) -> void:
	text = value % [hp, arm, speed]
