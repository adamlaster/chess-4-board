extends Control

var webview_plugin

func _ready() -> void:
	if Engine.has_singleton("GodotWebView"):
		webview_plugin = Engine.get_singleton("GodotWebView")
		webview_plugin.prepareBoardTouchPassthrough()
		webview_plugin.quit_app_requested.connect(_on_quit_app_requested)

	if not Board.is_on_device:
		return

	Board.initialize("00000000-0000-0000-0000-000000000000")
	Board.pause.pause_result_received.connect(_on_pause_result)

	# Wait for SystemOverlayService to finish binding before registering pause context
	var board_sdk = Engine.get_singleton("BoardSDK") if Engine.has_singleton("BoardSDK") else null
	if board_sdk:
		var wait_frames := 0
		while not board_sdk.are_services_ready() and wait_frames < 180:
			await get_tree().process_frame
			wait_frames += 1

	Board.pause.set_context({
		"game_name": "Chess 4 Board",
		"offer_save_option": false,
		"custom_buttons": [
			{ "id": "open_menu", "title": "Web Menu", "icon": Board.pause.ICON_SQUARE }
		]
	})

	if webview_plugin:
		# Hold splash image for 3 seconds before opening webview
		await get_tree().create_timer(3.0).timeout
		_open_my_webview()
		
func _on_quit_app_requested() -> void:
	Engine.max_fps = 60
	OS.low_processor_usage_mode = false
	if Board.is_on_device:
		Board.application.quit()
	else:
		get_tree().quit()
	
func _open_my_webview():
	# Drop Godot engine overhead to zero while WebView is active
	Engine.max_fps = 1
	OS.low_processor_usage_mode = true
	webview_plugin.open("https://www.chess.com")	
	
func _on_pause_result(result: BoardPauseResult) -> void:
	print("_on_pause_result fired!")
	match result.action:
		Board.pause.ACTION_RESUME:
			pass  # gameplay resumes
		Board.pause.ACTION_CUSTOM_BUTTON:
			if result.custom_button_id == "open_menu" and webview_plugin:
				webview_plugin.show_menu()
		Board.pause.ACTION_QUIT:
			Engine.max_fps = 60
			OS.low_processor_usage_mode = false
			Board.application.quit()
