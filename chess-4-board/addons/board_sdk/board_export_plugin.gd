@tool
extends EditorExportPlugin

# Registers the Board AAR with Godot's Android exporter.
#
# Per Godot 4.2+ Android Plugin v2 docs, this is the supported way to ship a
# native Android plugin: an EditorExportPlugin that returns the AAR paths
# from `_get_android_libraries()`. The AAR's AndroidManifest meta-data tag
# (`org.godotengine.plugin.v2.BoardSDK`) tells the engine which class to
# instantiate as the plugin singleton at runtime.

const PLUGIN_NAME := "BoardSDK"
const AAR_DEBUG := "res://addons/board_sdk/android/bin/debug/board.aar"
const AAR_RELEASE := "res://addons/board_sdk/android/bin/release/board.aar"


func _get_name() -> String:
	return PLUGIN_NAME


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	var release_path := ProjectSettings.globalize_path(AAR_RELEASE)
	if debug:
		return PackedStringArray([AAR_DEBUG])
	if not FileAccess.file_exists(release_path):
		# Release export with no release AAR — fall through to the debug AAR
		# so the build still succeeds, but loudly so devs notice they're
		# shipping debug artifacts.
		push_warning("[Board] Release AAR missing at %s — using debug AAR. Ship a release build before publishing." % AAR_RELEASE)
		return PackedStringArray([AAR_DEBUG])
	return PackedStringArray([AAR_RELEASE])
