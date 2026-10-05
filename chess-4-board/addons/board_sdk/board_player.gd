extends RefCounted

# Typed view of a player in the current session, from
# `Board.session.get_players()` / `get_active_profile()`.

class_name BoardPlayer

enum Type { PROFILE, GUEST }

## Persistent app-specific player id. Empty for guests.
var player_id: String = ""
## Session-unique id, stable for the life of the session. Pass to
## `Board.session.present_replace_player(session_id)`.
var session_id: int = -1
## Display name shown in OS UI.
var display_name: String = ""
var type: Type = Type.PROFILE
## Avatar identifier; pass to `Board.avatar.await_load_avatar(int(avatar_id))`.
var avatar_id: String = ""


static func from_dict(d: Dictionary) -> BoardPlayer:
	var p := BoardPlayer.new()
	p.player_id = String(d.get("player_id", ""))
	p.session_id = int(d.get("session_id", -1))
	p.display_name = String(d.get("name", ""))
	p.type = Type.GUEST if String(d.get("type", "")) == "guest" else Type.PROFILE
	p.avatar_id = String(d.get("avatar_id", ""))
	return p


func is_guest() -> bool:
	return type == Type.GUEST


func is_profile() -> bool:
	return type == Type.PROFILE
