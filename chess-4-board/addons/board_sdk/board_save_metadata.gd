extends RefCounted

# Typed view of a save game's metadata, from the `Board.save` await-helpers.

class_name BoardSaveMetadata

## Opaque save id. Pass to load / update / delete.
var id: String = ""
var description: String = ""
## Epoch milliseconds.
var created_at: int = 0
var updated_at: int = 0
## Accumulated play time in milliseconds, as supplied on create/update.
var played_time: int = 0
## Serialized payload size in bytes.
var file_size: int = 0
var game_version: String = ""
## Number of players associated with the save.
var player_count: int = 0


static func from_dict(d: Dictionary) -> BoardSaveMetadata:
	var m := BoardSaveMetadata.new()
	m.id = String(d.get("id", ""))
	m.description = String(d.get("description", ""))
	m.created_at = int(d.get("created_at", 0))
	m.updated_at = int(d.get("updated_at", 0))
	m.played_time = int(d.get("played_time", 0))
	m.file_size = int(d.get("file_size", 0))
	m.game_version = String(d.get("game_version", ""))
	m.player_count = int(d.get("player_count", 0))
	return m


## Whether this metadata refers to a real save (a load/list miss returns an
## empty id).
func is_valid() -> bool:
	return id != ""
