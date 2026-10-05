extends RefCounted

# Typed view of a pause-screen outcome, carried by
# `Board.pause.pause_result_received` and returned by `Board.pause.poll_result()`.

class_name BoardPauseResult

## What the user chose. Compare against BoardPauseModule.ACTION_* constants.
var action: String = ""
## For ACTION_CUSTOM_BUTTON, the id of the custom button that was pressed.
var custom_button_id: String = ""
## Audio-track levels the user adjusted on the pause screen, as
## `Array[Dictionary]` of `{ "id": String, "value": int }`.
var audio_tracks: Array = []


static func from_dict(d: Dictionary) -> BoardPauseResult:
	var r := BoardPauseResult.new()
	r.action = String(d.get("action", ""))
	r.custom_button_id = String(d.get("custom_button_id", ""))
	var tracks: Variant = d.get("audio_tracks", [])
	r.audio_tracks = tracks if tracks is Array else []
	return r


## Whether a result is present (an empty poll returns action == "").
func is_present() -> bool:
	return action != ""
