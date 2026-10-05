extends RefCounted

# System pause-screen integration.
#
# Configure the OS pause overlay via `set_context()`. The user's choice (Resume,
# Quit, Save & Quit, custom button) lands on `pause_result_received`.

class_name BoardPauseModule

const _PLUGIN_NAME := "BoardSDK"

# Action constants returned in `result.action`. Always match against these
# constants — the literal values are SCREAMING_SNAKE and may change between
# SDK releases.
const ACTION_RESUME := "RESUME"
const ACTION_QUIT := "EXIT_GAME_UNSAVED"
const ACTION_SAVE_AND_QUIT := "EXIT_GAME_SAVED"
const ACTION_CUSTOM_BUTTON := "CUSTOM_ACTION"

# Built-in icon names accepted by `BoardPauseButton.icon`.
const ICON_NONE := ""
const ICON_CIRCULAR_ARROW := "circulararrow"
const ICON_DOOR_WITH_ARROW := "doorwitharrow"
const ICON_LEFT_ARROW := "leftarrow"
const ICON_SQUARE := "square"

## Fires when the user dismisses the pause overlay with an action, carrying a
## typed [BoardPauseResult] (action, custom_button_id, audio_tracks).
signal pause_result_received(result: BoardPauseResult)

# Last-set context, kept so update_audio_tracks() can merge new track values
# without re-stating the rest of the config.
var _last_context: Dictionary = {}

var _root: Node


func _init(root: Node) -> void:
	_root = root
	if Engine.has_singleton(_PLUGIN_NAME):
		var p := Engine.get_singleton(_PLUGIN_NAME)
		p.connect("pause_result_received", _on_native_pause_result)


## Configure the system pause overlay.
##
## `context` schema (all optional):
##   {
##     "game_id":            String,
##     "game_name":          String,
##     "offer_save_option":  bool,
##     "custom_buttons":     Array[Dictionary{ id, title, icon }],
##     "audio_tracks":       Array[Dictionary{ id, name, value (0..100) }]
##   }
func set_context(context: Dictionary) -> void:
	_last_context = context.duplicate(true)
	_send_context(context)


## Update only the audio tracks while preserving everything else from the
## last `set_context` call. Useful for live volume sliders without re-sending
## the whole config every keystroke.
##
## `tracks` is the same Array shape as `set_context`'s `audio_tracks`:
##   [{ "id": "music", "name": "Music", "value": 0..100 }, …]
func update_audio_tracks(tracks: Array) -> void:
	if _last_context.is_empty():
		# Nothing to merge into yet — treat as a fresh set with just tracks.
		set_context({ "audio_tracks": tracks })
		return
	var merged := _last_context.duplicate(true)
	merged["audio_tracks"] = tracks
	_last_context = merged
	_send_context(merged)


func clear_context() -> void:
	_last_context = {}
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	Engine.get_singleton(_PLUGIN_NAME).clear_pause_context()


# --- Internals --------------------------------------------------------

func _send_context(context: Dictionary) -> void:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	# Native side accepts JSON. Translate snake_case keys → camelCase that the
	# plugin understands.
	#
	# Only include keys the caller actually provided. Forcing empty defaults
	# here (e.g. "gameId": "") trips the native-side validation and silently
	# disables the pause context — the system menu button stays live but the
	# tap looks like a no-op.
	var json := {}
	if context.has("game_id"):
		json["gameId"] = context["game_id"]
	if context.has("game_name"):
		json["gameName"] = context["game_name"]
	if context.has("offer_save_option"):
		json["offerSaveOption"] = context["offer_save_option"]
	if context.has("custom_buttons"):
		json["customButtons"] = context["custom_buttons"]
	if context.has("audio_tracks"):
		json["audioTracks"] = context["audio_tracks"]
	Engine.get_singleton(_PLUGIN_NAME).set_pause_context(JSON.stringify(json))


## Polling fallback for the `pause_result_received` signal. Returns a
## [BoardPauseResult] whose `is_present()` is false when no pause action has been
## committed yet.
##
## Prefer the signal: `Board.pause.pause_result_received.connect(...)`. This
## helper is a fallback for code that can't easily wire a signal handler — it
## consumes the same one-shot result the signal would deliver, so calling both
## in the same app causes one to miss the event.
func poll_result() -> BoardPauseResult:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return BoardPauseResult.new()
	return BoardPauseResult.from_dict(Engine.get_singleton(_PLUGIN_NAME).poll_pause_result())


func _on_native_pause_result(action: String, custom_button_id: String, audio_tracks: Array) -> void:
	var result := BoardPauseResult.new()
	result.action = action
	result.custom_button_id = custom_button_id
	result.audio_tracks = audio_tracks
	pause_result_received.emit(result)
