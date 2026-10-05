extends Node

# Board SDK runtime singleton — autoload as `Board`.
#
# Off-device (editor, desktop, simulator), `is_on_device` is false and all
# module APIs are no-ops or return defaults. Always check `Board.is_on_device`
# before calling any module method that depends on the OS.

const PLUGIN_NAME := "BoardSDK"

# The six module classes are registered globally via their `class_name`
# declarations (BoardInputModule, BoardSessionModule, ...), so they are
# referenced directly below without an explicit preload.

## True when the BoardSDK Android plugin is registered with the engine.
var is_on_device: bool:
	get: return Engine.has_singleton(PLUGIN_NAME)

## Touch / piece input. See `board_input.gd`.
var input: BoardInputModule

## Finger -> UI bridge: re-injects finger contacts as synthetic screen-touch
## events so Control/Button UI responds to fingers but never to Pieces. On by
## default on device. See `board_ui_input.gd`.
var ui_input: BoardUiInputModule

## Session and player management. See `board_session.gd`.
var session: BoardSessionModule

## Save game CRUD. See `board_save.gd`.
var save: BoardSaveModule

## Avatar PNG loader. See `board_avatar.gd`.
var avatar: BoardAvatarModule

## Pause screen / system menu integration. See `board_pause.gd`.
var pause: BoardPauseModule

## Application-lifecycle concerns (clean quit). See `board_application.gd`.
var application: BoardApplicationModule

func _ready() -> void:
	input = BoardInputModule.new(self)
	ui_input = BoardUiInputModule.new(self)
	session = BoardSessionModule.new(self)
	save = BoardSaveModule.new(self)
	avatar = BoardAvatarModule.new(self)
	pause = BoardPauseModule.new(self)
	application = BoardApplicationModule.new(self)

	# Status banner is debug-build only, so release games stay quiet on stdout.
	if OS.is_debug_build():
		if is_on_device:
			print("[Board] SDK ready")
		else:
			print("[Board] SDK loaded off-device (Engine.has_singleton('%s') == false)" % PLUGIN_NAME)


var _initialized := false

## Initialize the plugin with this game's app ID. Must be called once before
## any session/save/avatar/pause call. Subsequent calls are ignored (the first
## app ID wins).
func initialize(app_id: String) -> void:
	if not is_on_device:
		return
	if _initialized:
		return
	_initialized = true
	_plugin().initialize(app_id)


## Internal — module wrappers reach the plugin singleton through this.
func _plugin() -> Object:
	return Engine.get_singleton(PLUGIN_NAME)
