extends Button

var webview: WebView = null

func _ready():
	text = "Launch ChessKids.com"
	# Scales the button for a 24-inch touchscreen
	custom_minimum_size = Vector2(600, 200)
	add_theme_font_size_override("font_size", 48)
	webview = WebView.new()

func _on_button_pressed() -> void:
	webview.open("https://www.chesskids.com")
