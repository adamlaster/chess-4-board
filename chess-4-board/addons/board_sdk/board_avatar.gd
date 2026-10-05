extends RefCounted

# Avatar image loader.
#
# Loads and decodes the PNG for a player's avatar — the `avatar_id` carried by
# each player Dictionary returned from `Board.session.get_players()`. Results
# are cached (the same avatar is fetched over IPC only once) and concurrent
# requests for the same avatar share a single fetch. Mirrors the Unity SDK's
# cached BoardPlayer.avatar loader: pass a known player's `avatar_id`, not an
# arbitrary value.

class_name BoardAvatarModule

const _PLUGIN_NAME := "BoardSDK"

# Internal: the plugin pushes raw PNG bytes back on these, keyed by request id.
# Games use the await_* methods below, not these signals.
signal _png_loaded(request_id: int, png_bytes: PackedByteArray)
signal _png_failed(request_id: int, error: String)

# avatar_id -> ImageTexture, populated on first successful load.
var _cache: Dictionary = {}
# avatar_id -> true while a fetch for that avatar is in flight, so concurrent
# requests coalesce onto one IPC round-trip.
var _inflight: Dictionary = {}

var _root: Node


func _init(root: Node) -> void:
	_root = root
	if not Engine.has_singleton(_PLUGIN_NAME):
		return
	var p := Engine.get_singleton(_PLUGIN_NAME)
	p.connect("avatar_loaded", func(rid, b): _png_loaded.emit(rid, PackedByteArray(b)))
	p.connect("avatar_failed", func(rid, err): _png_failed.emit(rid, err))


## Load the avatar image for a player's `avatar_id` (from a player Dictionary
## returned by `Board.session.get_players()`). Returns a ready-to-display
## `ImageTexture`, or `null` on failure / off-device. Cached after the first
## successful load; concurrent calls for the same id share one fetch.
func await_load_avatar(avatar_id: int) -> ImageTexture:
	if _cache.has(avatar_id):
		return _cache[avatar_id]
	if not Engine.has_singleton(_PLUGIN_NAME):
		return null
	# Coalesce concurrent loads of the same avatar onto one fetch.
	if _inflight.has(avatar_id):
		while _inflight.has(avatar_id):
			await _root.get_tree().process_frame
		return _cache.get(avatar_id, null)

	_inflight[avatar_id] = true
	var tex := await _fetch_and_decode(avatar_id)
	if tex != null:
		_cache[avatar_id] = tex
	_inflight.erase(avatar_id)
	return tex


## The default avatar (id 0). Returns a ready-to-display `ImageTexture`, or
## `null` on failure / off-device.
func await_default_avatar() -> ImageTexture:
	return await await_load_avatar(0)


## Drop all cached avatar textures (e.g. after a profile/session reset).
func clear_cache() -> void:
	_cache.clear()


# Fetch the raw PNG for avatar_id and decode it to an ImageTexture. Returns null
# on any failure. Connects to both internal signals, filters by request id, and
# tears down BOTH connections the moment this request resolves — safe under
# concurrent loads and leak-free.
func _fetch_and_decode(avatar_id: int) -> ImageTexture:
	var rid: int = Engine.get_singleton(_PLUGIN_NAME).load_avatar_png(avatar_id)
	if rid < 0:
		return null
	var holder := { "done": false, "bytes": PackedByteArray() }
	holder["on_ok"] = func(r: int, b: PackedByteArray):
		if r != rid:
			return
		holder["done"] = true
		holder["bytes"] = PackedByteArray(b)
		_png_loaded.disconnect(holder["on_ok"])
		_png_failed.disconnect(holder["on_err"])
	holder["on_err"] = func(r: int, err: String):
		if r != rid:
			return
		holder["done"] = true
		push_error("[Board.avatar] load failed for avatar %d: %s" % [avatar_id, err])
		_png_loaded.disconnect(holder["on_ok"])
		_png_failed.disconnect(holder["on_err"])
	_png_loaded.connect(holder["on_ok"])
	_png_failed.connect(holder["on_err"])
	while not holder["done"]:
		await _root.get_tree().process_frame

	var bytes: PackedByteArray = holder["bytes"]
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		push_error("[Board.avatar] failed to decode PNG for avatar %d" % avatar_id)
		return null
	return ImageTexture.create_from_image(img)
