extends RefCounted

## Save game CRUD for the active app and profile.
##
## Most operations are asynchronous: the request method returns an [int]
## request id (or -1 off-device / on dispatch failure), and the result lands on
## a typed completion signal carrying that same id. Connect to the matching
## signal and compare the request id, or use the [code]await_*[/code] helpers to
## write straight-line [code]await[/code] code instead of wiring signals by hand.
##
## Naming: this module deliberately avoids the method name [code]load[/code].
## [code]load()[/code] is a GDScript built-in (it returns a Resource) and a
## same-named instance method shadows it and produces parse errors. Use
## [code]load_data[/code] instead.
##
## There is no direct delete: matching the Unity SDK, a save is removed by
## detaching its players via [method remove_players_from_save] or
## [method remove_active_profile_from_save]; the OS deletes the save once no
## players remain associated with it.

class_name BoardSaveModule

const _PLUGIN_NAME := "BoardSDK"

## Emitted when [method create] completes. [param metadata] is the saved game's
## [BoardSaveMetadata].
signal save_created(request_id: int, metadata: BoardSaveMetadata)

## Emitted when [method load_data] completes, carrying the raw save payload.
signal save_loaded(request_id: int, data: PackedByteArray)

## Emitted when [method list] completes, carrying an `Array[BoardSaveMetadata]`.
signal save_listed(request_id: int, saves: Array)

## Emitted when [method update] completes.
signal save_updated(request_id: int)

## Emitted when [method remove_players_from_save] completes.
signal save_players_removed(request_id: int)

## Emitted when [method remove_active_profile_from_save] completes.
signal save_active_profile_removed(request_id: int)

## Emitted when [method load_cover_image] completes, carrying the cover PNG bytes.
signal save_cover_image_loaded(request_id: int, png_bytes: PackedByteArray)

## Emitted when any save operation fails. [param request_id] matches the failed
## request; [param error] is a human-readable message.
signal save_failed(request_id: int, error: String)

var _root: Node


func _init(root: Node) -> void:
	_root = root
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	var p := Engine.get_singleton(_PLUGIN_NAME)
	# Re-emit the plugin's native completion signals as this module's typed
	# signals, so games connect to a stable GDScript surface.
	p.connect("save_created", func(rid, meta): save_created.emit(rid, BoardSaveMetadata.from_dict(meta)))
	p.connect("save_loaded", func(rid, data): save_loaded.emit(rid, PackedByteArray(data)))
	p.connect("save_listed", func(rid, saves): save_listed.emit(rid, _to_metadata_array(saves)))
	p.connect("save_updated", func(rid): save_updated.emit(rid))
	p.connect("save_players_removed", func(rid): save_players_removed.emit(rid))
	p.connect("save_active_profile_removed", func(rid): save_active_profile_removed.emit(rid))
	p.connect("save_cover_image_loaded", func(rid, b): save_cover_image_loaded.emit(rid, PackedByteArray(b)))
	p.connect("save_failed", func(rid, err): save_failed.emit(rid, err))


# ---- Fire-and-forget request methods ---------------------------------
# Each returns the request id to correlate with a completion signal, or -1
# off-device. Prefer the await_* helpers below unless you are wiring signals
# yourself.

## Create a new save. [param data] is the opaque game payload; [param played_time_ms]
## and [param game_version] are stored as metadata. Resolves on [signal save_created].
## `cover_png` is optional PNG bytes for the save's cover thumbnail (empty = none).
func create(description: String, data: PackedByteArray, played_time_ms: int, game_version: String, cover_png: PackedByteArray = PackedByteArray()) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).create_save(description, data, played_time_ms, game_version, cover_png)


## Load a save's payload by id. Resolves on [signal save_loaded].
func load_data(save_id: String) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).load_save(save_id)


## List the current app + profile's saves. Resolves on [signal save_listed].
func list() -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).list_saves()


## Overwrite an existing save's payload and metadata. Resolves on [signal save_updated].
func update(save_id: String, description: String, data: PackedByteArray, played_time_ms: int, game_version: String, cover_png: PackedByteArray = PackedByteArray()) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).update_save(save_id, description, data, played_time_ms, game_version, cover_png)


## Remove the session's players from a save. The OS deletes the save once no
## players remain associated with it. Resolves on [signal save_players_removed].
func remove_players_from_save(save_id: String) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).remove_players_from_save(save_id)


## Remove just the active profile from a save. Resolves on
## [signal save_active_profile_removed].
func remove_active_profile_from_save(save_id: String) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).remove_active_profile_from_save(save_id)


## Load a save's cover image (PNG). Resolves on [signal save_cover_image_loaded].
func load_cover_image(save_id: String) -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return -1
	return Engine.get_singleton(_PLUGIN_NAME).load_save_cover_image(save_id)


# ---- Limits (synchronous) --------------------------------------------

## Maximum payload size in bytes accepted by [method create] / [method update].
## Returns 0 off-device.
func get_max_data_size() -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return 0
	return Engine.get_singleton(_PLUGIN_NAME).get_max_save_data_size()


## Total per-app save-storage budget in bytes. Returns 0 off-device.
func get_max_app_storage_size() -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return 0
	return Engine.get_singleton(_PLUGIN_NAME).get_max_app_storage_size()


## Maximum length in characters of a save [code]description[/code]. Returns 0 off-device.
func get_max_description_length() -> int:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return 0
	return Engine.get_singleton(_PLUGIN_NAME).get_max_save_description_length()


## Current save-storage usage for this app, as a Dictionary with keys:
##   total_storage     int    total per-app budget in bytes
##   used_storage      int    bytes currently used by this app's saves
##   remaining_storage int    bytes still available
##   usage_percentage  float  used / total, 0.0–1.0
## Use it to render a storage meter or pre-flight whether a new save will fit.
## Returns an empty Dictionary off-device. Synchronous (a quick on-device query).
func get_app_storage_info() -> Dictionary:
	if not Engine.has_singleton(_PLUGIN_NAME):
		return {}
	return Engine.get_singleton(_PLUGIN_NAME).get_app_storage_info()


# ---- await-style helpers ---------------------------------------------
#
# These wrap the request + signal pattern so callers can await a single call.
# GDScript's await can't natively race two signals, so each helper connects to
# both the success signal and save_failed, filters by request id, and tears
# down BOTH connections the moment its own request resolves. That makes the
# helpers safe under concurrent in-flight requests (an unrelated request's
# completion is ignored, never consumed) and leak-free (no dangling connection
# survives the call).

## await [method list]. Returns an `Array[BoardSaveMetadata]`, empty on failure.
func await_list() -> Array[BoardSaveMetadata]:
	var h: Dictionary = await _await_value(list(), save_listed, "list")
	var out: Array[BoardSaveMetadata] = []
	if h["ok"]:
		out.assign(h["value"])
	return out


## await [method load_data]. Returns the payload, or an empty PackedByteArray on failure.
func await_load(save_id: String) -> PackedByteArray:
	var h: Dictionary = await _await_value(load_data(save_id), save_loaded, "load")
	if not h["ok"]:
		return PackedByteArray()
	var result: PackedByteArray = h["value"]
	return result


## await [method create]. Returns the new save's [BoardSaveMetadata], or null on failure.
func await_create(description: String, data: PackedByteArray, played_time_ms: int, game_version: String, cover_png: PackedByteArray = PackedByteArray()) -> BoardSaveMetadata:
	var h: Dictionary = await _await_value(create(description, data, played_time_ms, game_version, cover_png), save_created, "create")
	return h["value"] if h["ok"] else null


## await [method load_cover_image]. Returns the PNG bytes, or an empty PackedByteArray on failure.
func await_load_cover_image(save_id: String) -> PackedByteArray:
	var h: Dictionary = await _await_value(load_cover_image(save_id), save_cover_image_loaded, "load_cover_image")
	if not h["ok"]:
		return PackedByteArray()
	var result: PackedByteArray = h["value"]
	return result


## await [method update]. Returns true on success, false on failure.
func await_update(save_id: String, description: String, data: PackedByteArray, played_time_ms: int, game_version: String, cover_png: PackedByteArray = PackedByteArray()) -> bool:
	return await _await_ack(update(save_id, description, data, played_time_ms, game_version, cover_png), save_updated, "update")


## await [method remove_players_from_save]. Returns true on success, false on failure.
func await_remove_players(save_id: String) -> bool:
	return await _await_ack(remove_players_from_save(save_id), save_players_removed, "remove_players")


## await [method remove_active_profile_from_save]. Returns true on success, false on failure.
func await_remove_active_profile(save_id: String) -> bool:
	return await _await_ack(remove_active_profile_from_save(save_id), save_active_profile_removed, "remove_active_profile")


# ---- await internals -------------------------------------------------

# Await a value-carrying success signal raced against save_failed, filtered to
# `rid`. Returns { "ok": bool, "value": Variant }, tearing down both
# connections on resolution. The Callables are stored in the holder Dictionary
# so each can reference the other for disconnect: GDScript lambdas capture the
# holder reference (a Dictionary is a reference type), not the not-yet-assigned
# local Callables.
func _await_value(rid: int, success_signal: Signal, op_name: String) -> Dictionary:
	var holder := { "done": false, "ok": false, "value": null }
	if rid < 0:
		return holder
	holder["on_ok"] = func(r: int, payload):
		if r != rid:
			return
		holder["done"] = true
		holder["ok"] = true
		holder["value"] = payload
		success_signal.disconnect(holder["on_ok"])
		save_failed.disconnect(holder["on_err"])
	holder["on_err"] = func(r: int, err: String):
		if r != rid:
			return
		holder["done"] = true
		push_error("[Board.save] %s failed: %s" % [op_name, err])
		success_signal.disconnect(holder["on_ok"])
		save_failed.disconnect(holder["on_err"])
	success_signal.connect(holder["on_ok"])
	save_failed.connect(holder["on_err"])
	while not holder["done"]:
		await _root.get_tree().process_frame
	return holder


# Await an acknowledgement-only success signal (payload is just the request id)
# raced against save_failed, filtered to `rid`. Returns true on success.
func _await_ack(rid: int, success_signal: Signal, op_name: String) -> bool:
	var holder := { "done": false, "ok": false }
	if rid < 0:
		return false
	holder["on_ok"] = func(r: int):
		if r != rid:
			return
		holder["done"] = true
		holder["ok"] = true
		success_signal.disconnect(holder["on_ok"])
		save_failed.disconnect(holder["on_err"])
	holder["on_err"] = func(r: int, err: String):
		if r != rid:
			return
		holder["done"] = true
		push_error("[Board.save] %s failed: %s" % [op_name, err])
		success_signal.disconnect(holder["on_ok"])
		save_failed.disconnect(holder["on_err"])
	success_signal.connect(holder["on_ok"])
	save_failed.connect(holder["on_err"])
	while not holder["done"]:
		await _root.get_tree().process_frame
	return holder["ok"]


# Convert the plugin's Array of metadata Dictionaries into typed BoardSaveMetadata.
func _to_metadata_array(dicts: Array) -> Array[BoardSaveMetadata]:
	var out: Array[BoardSaveMetadata] = []
	for d in dicts:
		out.append(BoardSaveMetadata.from_dict(d))
	return out
