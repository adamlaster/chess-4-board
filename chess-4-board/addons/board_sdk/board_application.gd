extends RefCounted

# Application-lifecycle module: app-wide concerns that don't belong to any
# of the input/session/save/avatar/pause domains. Currently just clean app
# termination. (The system menu button — the top-right pause affordance — is
# owned and shown by the OS, not the SDK; games can't toggle its visibility.)
#
# Godot apps handle pause/resume/focus-loss via `NOTIFICATION_APPLICATION_*` on
# any Node — those don't need to route through Board.

class_name BoardApplicationModule

const _PLUGIN_NAME := "BoardSDK"

var _root: Node


func _init(root: Node) -> void:
	_root = root


## Terminate the calling app cleanly. Equivalent to the user swiping the app
## away in Recent Apps. Fire-and-forget; the process is gone before this
## returns.
func quit() -> void:
	if not Engine.has_singleton(_PLUGIN_NAME):
		# Off-device: fall through to the engine's quit so the editor / desktop
		# build can also exercise this code path.
		_root.get_tree().quit()
		return
	Engine.get_singleton(_PLUGIN_NAME).terminate_application()
