extends RefCounted

# Touch / piece input module.
#
# `Board.input.contacts_received` fires every inference frame (~60 fps once
# subscribed). Subscribe via `Board.input.subscribe()`. The signal payload is
# `Array[Dictionary]` with these keys:
#
#   contact_id   int        Stable across frames for the same physical contact
#   x            float      Display pixels, Y-down
#   y            float      Display pixels, Y-down
#   orientation  float      Degrees in [0, 360), screen-space — feeding into
#                           Vector2(cos θ, sin θ) yields a unit vector
#                           pointing in the same direction the physical
#                           piece is facing. Only meaningful for glyphs.
#   type_id      int        BoardContactType: 0 finger, 1 glyph
#   phase_id     int        BoardContactPhase: 1 began, 2 moved, 3 ended,
#                           4 canceled, 5 stationary
#   glyph_id     int        0 for finger; 1+ for piece type
#   is_touched   bool       Piece is being physically held by a hand
#   frame_number int        Kernel frame number for cross-layer correlation

class_name BoardInputModule

const _PLUGIN_NAME := "BoardSDK"

# Contact type and lifecycle-phase constants, for code that reads a raw contact
# Dictionary's `type_id` / `phase_id` directly. These mirror the BoardContact.Type
# and BoardContact.Phase enums (same values) — prefer those when you wrap a contact
# with BoardContact.from_dict(). Kept as literals because GDScript can't resolve a
# `const` initialized from another class_name's enum.
const TYPE_FINGER := 0
const TYPE_GLYPH := 1
const TYPE_BLOB := 2
const PHASE_NONE := 0
const PHASE_BEGAN := 1
const PHASE_MOVED := 2
const PHASE_ENDED := 3
const PHASE_CANCELED := 4
const PHASE_STATIONARY := 5

## Fires every inference frame (~60 fps once subscribed) with the current
## `Array[Dictionary]` of contacts. Stationary contacts persist across frames.
##
## This is the single touch surface: each contact carries `phase_id` (BEGAN/
## MOVED/ENDED/CANCELED/STATIONARY) and `is_touched`. A game that wants discrete
## edges (tap-down / tap-up, piece-lifted) keeps its own previous-frame map and
## diffs it — the SDK does not derive edge events, matching the Unity SDK's
## per-frame snapshot model.
##
## Entries are raw `Dictionary`s (kept allocation-free for the per-frame stream);
## wrap one with `BoardContact.from_dict(c)` when you want typed fields, the
## `Type`/`Phase` enums, and the `facing()` / `is_piece()` helpers.
signal contacts_received(contacts: Array)

var _root: Node
var _subscribed := false

# Active contacts indexed by contact_id. Persists across frames so stationary
# contacts (which the native side stops emitting once they stop moving) keep
# rendering on the game side.
var _active: Dictionary = {}


func _init(root: Node) -> void:
	_root = root
	if Engine.has_singleton(_PLUGIN_NAME):
		Engine.get_singleton(_PLUGIN_NAME).connect("on_contacts", _on_contacts_native)


## Load a Piece Set Model and start the touch detector. Required once after
## `Board.initialize()` before any contacts will fire.
##
## `model_asset` is the path of a `.tflite` under `res://assets/` (e.g.
## `"models/arcade_v1.3.7.tflite"`). The SDK reads it from your exported project
## (the PCK) and hands it to the native detector, so a standard Godot Android
## export works with no special asset staging. The SDK bundles no model itself —
## each game's Piece Set determines the right one.
##
## Tracker parameter defaults match the Board Arcade Piece Set; pass other
## values when targeting a different Piece Set or for a tighter feel.
##
## Returns `true` if both load and activation succeeded.
func activate(model_asset: String,
              position_smoothing: float = 0.035,
              rotation_smoothing: float = 0.004,
              persistence: int = 4,
              fast_tracking: bool = true) -> bool:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return false
	var model_path := _extract_model(model_asset)
	if model_path.is_empty():
		return false
	return Engine.get_singleton(_PLUGIN_NAME).activate_touch(
		model_path, position_smoothing, rotation_smoothing, persistence, fast_tracking)


# The native detector loads a model from a real filesystem path, but a bundled
# model lives inside the exported PCK (res://), which isn't a path the native
# side can open. Extract it once to user:// (a writable dir) and return the
# absolute path. Returns "" on failure.
func _extract_model(model_asset: String) -> String:
	var res_path := "res://assets/" + model_asset
	if not FileAccess.file_exists(res_path):
		push_error("[Board.input] model not found at %s — bundle it under res://assets/ (e.g. assets/models/<file>.tflite)." % res_path)
		return ""
	var data := FileAccess.get_file_as_bytes(res_path)
	if data.is_empty():
		push_error("[Board.input] model is empty or unreadable: %s" % res_path)
		return ""
	var dest_dir := "user://board_models"
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dest := "%s/%s" % [dest_dir, model_asset.get_file()]
	# Re-extract only when missing or a different size, so repeated activate()
	# calls don't rewrite the same model each time.
	var needs_write := true
	if FileAccess.file_exists(dest):
		var existing := FileAccess.open(dest, FileAccess.READ)
		if existing != null:
			needs_write = existing.get_length() != data.size()
			existing.close()
	if needs_write:
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out == null:
			push_error("[Board.input] couldn't write model to %s (%s)" % [dest, error_string(FileAccess.get_open_error())])
			return ""
		out.store_buffer(data)
		out.close()
	return ProjectSettings.globalize_path(dest)


## Begin the touch push channel. Idempotent. Requires a prior `activate()`
## to actually deliver contacts — `subscribe()` only registers the signal
## sink; `activate()` is what turns on the upstream HAL.
func subscribe() -> void:
	if _subscribed:
		return
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	Engine.get_singleton(_PLUGIN_NAME).subscribe_touch()
	_subscribed = true


## Stop the touch push channel.
func unsubscribe() -> void:
	if not _subscribed:
		return
	if Engine.has_singleton(_PLUGIN_NAME):
		Engine.get_singleton(_PLUGIN_NAME).unsubscribe_touch()
	_subscribed = false


## Whether the push channel is currently active.
var is_subscribed: bool:
	get: return _subscribed


## Snapshot of currently-active contacts (no subscription required).
func get_current_contacts() -> Array:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return []
	return Engine.get_singleton(_PLUGIN_NAME).get_current_contacts()


func _on_contacts_native(raw_frame: Array) -> void:
	# The native side only emits frames when something changes
	# (Began/Moved/Ended/Canceled). Stationary contacts must be carried
	# forward client-side, otherwise lifting-and-holding makes them vanish.
	var updated_ids := {}
	for c in raw_frame:
		var id: int = int(c.get("contact_id", -1))
		if id < 0:
			continue
		var phase: int = int(c.get("phase_id", PHASE_BEGAN))
		if phase == PHASE_ENDED or phase == PHASE_CANCELED:
			_active.erase(id)
		else:
			_active[id] = c
			updated_ids[id] = true

	# Contacts in our map but missing from this frame become Stationary.
	# Mutate the cached Dictionary in place so subsequent frames keep the
	# stationary phase.
	for id in _active.keys():
		if not updated_ids.has(id):
			_active[id]["phase_id"] = PHASE_STATIONARY

	contacts_received.emit(_active.values())
