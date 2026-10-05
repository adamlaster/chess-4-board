extends PanelContainer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#Board.initialize("00000000-0000-0000-0000-000000000000")
	#Board.input.activate("") 
	## Configure the menu. All keys are optional; omit ones you don't use.
	#Board.pause.set_context({
		#"game_name": "Chess 4 Board",
		#"offer_save_option": false
	#})
#
	## Results arrive on a signal.
	#Board.pause.pause_result_received.connect(_on_pause_result)
	pass


func _on_pause_result(result: BoardPauseResult) -> void:
	print("_on_pause_result fired!")
	match result.action:
		Board.pause.ACTION_RESUME:
			pass  # gameplay resumes
		Board.pause.ACTION_QUIT:
			Board.application.quit()
