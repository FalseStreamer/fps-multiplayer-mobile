extends StaticBody3D


func take_damage(amount: int, headshot: bool) -> void:
	self.hide()
	print("Enemy hit!!! | ",amount, " is headshot: ", headshot)
	await get_tree().create_timer(7).timeout
	self.show()
