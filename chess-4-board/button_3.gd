extends Button

func _ready():
	text = "Quit"
	# Scales the button for a 24-inch touchscreen
	custom_minimum_size = Vector2(600, 200)
	add_theme_font_size_override("font_size", 48)
	

func _on_button_pressed() -> void:
	get_tree().quit()
	
