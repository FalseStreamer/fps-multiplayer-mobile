extends Label


var ammo = "Ammo: %d / %d"

func ammo_update(current: int, reserve: int):
	text = ammo % [current, reserve]
