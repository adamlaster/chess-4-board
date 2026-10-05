extends RefCounted

# Finger -> UI input bridge.
#
# On Board hardware the SDK swallows all raw Android motion events (see
# BoardGodotPlugin.onMainCreate), because the touch controller reports a
# Piece's Glyph as ordinary capacitive touch points that are indistinguishable
# from a finger at the MotionEvent layer. Only the classified Board pipeline
# knows finger from Piece. If we let raw touches through, a Piece placed on a
# Button would press it — the bug this module exists to prevent.
#
# So Godot's built-in UI (Control / Button hit-testing, `_gui_input`) receives
# nothing from the OS. This module re-injects the *finger* contacts from the
# Board pipeline as synthetic `InputEventScreenTouch` / `InputEventScreenDrag`
# via `Input.parse_input_event`, so the UI responds to fingers exactly as it
# would to normal touches — but never to Pieces, which are filtered out here.
#
# This mirrors the Unity SDK, which pairs the same native touch swallow with
# `BoardUIInputModule` (a `BoardContactType.Finger`-masked PointerInputModule).
#
# Requirements / limitations:
#   * Rides the same touch stream the game uses: contacts only flow after
#     `Board.input.activate(model)` + `Board.input.subscribe()`. Before a model
#     is active there are no contacts, so on-device UI receives no input (raw
#     touches are swallowed). Activate the detector early if you show menus
#     before gameplay.
#   * Godot's `input_devices/pointing/emulate_mouse_from_touch` (on by default)
#     turns the primary touch (index 0) into mouse events, which is what drives
#     standard `Button`/`Control` clicks. We always allocate the lowest free
#     index first so the first finger down maps to index 0.

class_name BoardUiInputModule

const _PLUGIN_NAME := "BoardSDK"

# Godot supports a fixed number of simultaneous touch indices. Index 0 is the
# one Godot emulates the mouse from, so menus only ever need the primary; the
# extra slots let multi-finger `_gui_input` handlers still work.
const _MAX_SLOTS := 16

var _root: Node
var _enabled := true

# contact_id -> assigned touch index (Godot's InputEventScreen*.index).
var _slots: Dictionary = {}
# Pool of free indices, kept sorted ascending so the primary finger gets 0.
var _free: Array = []
# touch index -> last reported position, for computing drag deltas.
var _last_pos: Dictionary = {}


func _init(root: Node) -> void:
	_root = root
	_reset_slots()
	if Engine.has_singleton(_PLUGIN_NAME):
		# Listen to the raw native frame (not Board.input.contacts_received):
		# we need the BEGAN/ENDED phases to press and release the synthetic
		# touch, and contacts_received drops ENDED contacts before emitting.
		Engine.get_singleton(_PLUGIN_NAME).connect("on_contacts", _on_contacts_native)


## Enable or disable finger -> UI synthesis. On by default on device. Disable
## if your game drives all of its UI from `Board.input.contacts_received`
## directly and doesn't want synthetic events reaching Control nodes.
func set_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return
	_enabled = enabled
	if not enabled:
		_release_all()


## Whether finger -> UI synthesis is currently active.
var is_enabled: bool:
	get: return _enabled


func _on_contacts_native(raw_frame: Array) -> void:
	if not _enabled:
		return
	for c in raw_frame:
		_inject_contact(c)


func _inject_contact(c: Dictionary) -> void:
	var contact_id := int(c.get("contact_id", -1))
	if contact_id < 0:
		return

	var phase := int(c.get("phase_id", BoardInputModule.PHASE_BEGAN))
	var pos := Vector2(float(c.get("x", 0.0)), float(c.get("y", 0.0)))

	# Pieces never drive the UI — that's the whole point of this module. The
	# finger/Piece distinction lives in glyph_id (0 = finger, 1+ = identified
	# Piece), NOT type_id: the tracker stamps every contact on the Godot channel
	# as GLYPH, so type_id is always 1 here. This matches BoardContact.is_piece()
	# and the SDK's "use glyph_id, not type_id" rule.
	if int(c.get("glyph_id", 0)) > 0:
		return

	if phase == BoardInputModule.PHASE_BEGAN:
		_press(contact_id, pos)
	elif phase == BoardInputModule.PHASE_MOVED:
		if _slots.has(contact_id):
			var idx := int(_slots[contact_id])
			var prev: Vector2 = _last_pos.get(idx, pos)
			_emit_drag(idx, pos, pos - prev)
			_last_pos[idx] = pos
		else:
			# Began was missed (e.g. enabled mid-touch); treat as a press.
			_press(contact_id, pos)
	elif phase == BoardInputModule.PHASE_ENDED or phase == BoardInputModule.PHASE_CANCELED:
		if _slots.has(contact_id):
			var idx := int(_slots[contact_id])
			_emit_touch(idx, pos, false, phase == BoardInputModule.PHASE_CANCELED)
			_free_slot(contact_id)
	# PHASE_STATIONARY is never emitted on the raw native channel, so a finger
	# held still produces no events between its press and release — exactly what
	# a Button expects.


func _press(contact_id: int, pos: Vector2) -> void:
	var idx := _alloc_slot(contact_id)
	if idx < 0:
		return
	_last_pos[idx] = pos
	_emit_touch(idx, pos, true, false)


func _alloc_slot(contact_id: int) -> int:
	if _slots.has(contact_id):
		return int(_slots[contact_id])
	if _free.is_empty():
		return -1
	var idx: int = _free.pop_front()
	_slots[contact_id] = idx
	return idx


func _free_slot(contact_id: int) -> void:
	if not _slots.has(contact_id):
		return
	var idx: int = _slots[contact_id]
	_slots.erase(contact_id)
	_last_pos.erase(idx)
	if not _free.has(idx):
		_free.append(idx)
		_free.sort()


func _release_all() -> void:
	# Cancel any held touches so the UI doesn't get stuck in a pressed state.
	for contact_id in _slots.keys():
		var idx := int(_slots[contact_id])
		var pos: Vector2 = _last_pos.get(idx, Vector2.ZERO)
		_emit_touch(idx, pos, false, true)
	_reset_slots()


func _reset_slots() -> void:
	_slots.clear()
	_last_pos.clear()
	_free.clear()
	for i in range(_MAX_SLOTS):
		_free.append(i)


func _emit_touch(index: int, pos: Vector2, pressed: bool, canceled: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	ev.canceled = canceled
	Input.parse_input_event(ev)


func _emit_drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	Input.parse_input_event(ev)
