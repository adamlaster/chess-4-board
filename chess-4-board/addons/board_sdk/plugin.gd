@tool
extends EditorPlugin

# EditorPlugin entry point for the Board SDK.
#
# Its only job is to register the EditorExportPlugin that contributes the Board
# AAR (and any future companion AARs) to Android exports. The runtime API is
# exposed via the `Board` autoload that game projects add manually (or via this
# plugin's enable hook if we add that later).

const BoardExportPlugin := preload("res://addons/board_sdk/board_export_plugin.gd")

var _export_plugin: BoardExportPlugin


func _enter_tree() -> void:
	_export_plugin = BoardExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
