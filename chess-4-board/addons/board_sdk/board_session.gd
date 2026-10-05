extends RefCounted

# Session / player management module.
#
# Players are returned as typed `BoardPlayer` objects (player_id, session_id,
# display_name, type, avatar_id, plus is_guest()/is_profile()). See board_player.gd.

class_name BoardSessionModule

const _PLUGIN_NAME := "BoardSDK"

const TYPE_PROFILE := "profile"
const TYPE_GUEST := "guest"

## Fires after the OS player-selector overlay dismisses successfully (a player
## was picked or removed). `request_id` matches the value returned from
## `present_add_player()` / `present_replace_player()`.
##
## Emit is deferred to the next idle frame so callers that `await` immediately
## after `present_add_player()` don't miss a signal that fires synchronously
## from the underlying Java emit.
signal player_selector_completed(request_id: int)

## Fires when the player-selector overlay can't open or the user dismisses
## without picking. `reason` is "dismissed" for user-cancel.
signal player_selector_failed(request_id: int, reason: String)

## Fires whenever the player-selector overlay settles, regardless of outcome.
## `ok` is true if a player was picked, false on dismiss / open failure.
## Use this when callers don't need to distinguish success from dismissal —
## it removes the need to race two signals manually.
signal player_selector_finished(request_id: int, ok: bool)

## Fires whenever the active player list mutates (a player added/removed/replaced
## via the OS selector overlay, profile selection, etc.). No payload — re-query
## `get_players()` after to read the new state.
signal players_changed

var _root: Node


func _init(root: Node) -> void:
	_root = root
	if Engine.has_singleton(_PLUGIN_NAME):
		var p := Engine.get_singleton(_PLUGIN_NAME)
		p.connect("player_selector_completed", _on_selector_completed)
		p.connect("player_selector_failed", _on_selector_failed)
		p.connect("players_changed", _on_players_changed)


func _on_selector_completed(rid: int) -> void:
	# Defer so synchronous emits (e.g. early failure paths) land after the
	# caller's `await` has actually started listening.
	call_deferred("_emit_selector_completed", rid)


func _on_selector_failed(rid: int, reason: String) -> void:
	call_deferred("_emit_selector_failed", rid, reason)


func _on_players_changed() -> void:
	call_deferred("_emit_players_changed")


func _emit_selector_completed(rid: int) -> void:
	player_selector_completed.emit(rid)
	player_selector_finished.emit(rid, true)


func _emit_selector_failed(rid: int, reason: String) -> void:
	player_selector_failed.emit(rid, reason)
	player_selector_finished.emit(rid, false)


func _emit_players_changed() -> void:
	players_changed.emit()


## All players in the current session, as typed `BoardPlayer` objects.
func get_players() -> Array[BoardPlayer]:
	var out: Array[BoardPlayer] = []
	if not Engine.has_singleton(_PLUGIN_NAME):
		return out
	for d in Engine.get_singleton(_PLUGIN_NAME).get_players():
		out.append(BoardPlayer.from_dict(d))
	return out


func get_player_count() -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return 0
	return Engine.get_singleton(_PLUGIN_NAME).get_player_count()


# Note: there is no add_guest / remove_player. The session roster is OS-owned;
# players are added, removed, or replaced only through the OS selector overlay
# (present_add_player / present_replace_player) or reset_players(). A game can't
# silently change who's playing. This matches the Unity SDK.


## Reset the session to just the active profile.
func reset_players() -> bool:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return false
	return Engine.get_singleton(_PLUGIN_NAME).reset_players()


## Whether the session manager has finished its initial profile load.
func is_session_ready() -> bool:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return false
	return Engine.get_singleton(_PLUGIN_NAME).is_session_ready()


## Whether the OS-level services are connected.
func are_services_ready() -> bool:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return false
	return Engine.get_singleton(_PLUGIN_NAME).are_services_ready()


## The system-wide active profile as a `BoardPlayer`, or null if none.
func get_active_profile() -> BoardPlayer:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return null
	var d: Dictionary = Engine.get_singleton(_PLUGIN_NAME).get_active_profile()
	return BoardPlayer.from_dict(d) if not d.is_empty() else null


## Show the OS player selector to add a new player. Returns the request_id;
## await `player_selector_completed` (or `player_selector_failed`) for the
## result. Returns -1 if the plugin isn't available.
##
## `ai_type_indices` restricts the selector's "Add AI" options to a subset of
## the types registered via `set_ai_player_types()`; leave it empty to offer
## all registered types.
func present_add_player(ai_type_indices: PackedInt32Array = PackedInt32Array()) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).present_add_player_selector(ai_type_indices)


## Show the OS player selector to replace `session_id`. Returns the request_id;
## await `player_selector_completed` for the result. Returns -1 if the plugin
## isn't available.
##
## `ai_type_indices` restricts the selector's "Add AI" options to a subset of
## the registered types; leave it empty to offer all of them.
func present_replace_player(session_id: int, ai_type_indices: PackedInt32Array = PackedInt32Array()) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).present_replace_player_selector(session_id, ai_type_indices)


func show_profile_switcher() -> void:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	Engine.get_singleton(_PLUGIN_NAME).show_profile_switcher()


func hide_profile_switcher() -> void:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	Engine.get_singleton(_PLUGIN_NAME).hide_profile_switcher()


## Register AI player types this game supports. Used by the OS player selector
## to populate the "Add AI" UI.
##
## `types` is an Array of Dictionary entries, each with these keys:
##   `name`        String   Short label shown in the picker (e.g. "Easy")
##   `description` String   One-line explanation shown below the label
##
## Example:
##   Board.session.set_ai_player_types([
##       { "name": "Easy", "description": "Plays defensively" },
##       { "name": "Hard", "description": "Plans 3 turns ahead" },
##   ])
##
## Pass an empty array to clear the registration. Order is preserved in the UI.
func set_ai_player_types(types: Array) -> void:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	var names := PackedStringArray()
	var descriptions := PackedStringArray()
	for t in types:
		names.append(str(t.get("name", "")))
		descriptions.append(str(t.get("description", "")))
	Engine.get_singleton(_PLUGIN_NAME).set_ai_player_types(names, descriptions)
