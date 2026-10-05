# Board Godot SDK — Consumer Guide

You're reading this because the Board Godot SDK addon is installed in this project's `addons/board_sdk/`. This file tells your coding agent (Claude, Codex, Cursor, Gemini CLI, or any other) — and any human who reads it — how to use the SDK to build a working Board game. (Claude Code reads the sibling `CLAUDE.md`, which simply imports this file, so both point at the same content.)

If you're starting a brand-new project and you're using Claude Code, the fastest path is the bundled skill: install it once with `cp -R <sdk>/skills/bootstrap-board-godot-game ~/.claude/skills/`, then run `/bootstrap-board-godot-game`. It walks through the questions, generates the project, and prints next steps. (On other agents, follow the setup checklist below by hand.)

## What is Board?

Board is a 23.8" 1080p landscape touch-display console (MediaTek Genio 700, 4 GB RAM, WiFi 6) designed for tabletop play. Apps are sideloaded Android packages. Beyond raw fingers, Board's touch sensor recognizes the conductive **Glyph** pattern on the base of each physical **Piece** in a **Piece Set**, giving games per-piece identity, position, orientation, and a hand-presence (`is_touched`) signal. The SDK exposes that input plus the OS-level session, save, avatar, and pause services.

## Bootstrapping a New Game

The minimum viable scene:

```gdscript
extends Node

const APP_ID := "00000000-0000-0000-0000-000000000000"  # replace with your app ID
const PIECE_SET_MODEL := "models/arcade_v1.3.7.tflite"  # in res://assets/

func _ready() -> void:
    if not Board.is_on_device:
        return
    Board.initialize(APP_ID)
    Board.input.contacts_received.connect(_on_contacts)
    Board.input.activate(PIECE_SET_MODEL)
    Board.input.subscribe()

func _on_contacts(contacts: Array) -> void:
    # Per-frame snapshot — runs every inference frame (~60 fps).
    for c in contacts:
        var glyph_id := int(c.get("glyph_id", 0))
        if glyph_id == 0:
            continue  # finger (no piece)
        # do something with the piece at (c.x, c.y), orientation = c.orientation
```

Setup checklist:

1. Drop the addon into `addons/board_sdk/`. The `Board` autoload registers automatically when the EditorPlugin is enabled in `Project → Project Settings → Plugins`.
2. In `project.godot`:
   - `display/window/handheld/orientation=0` (landscape sensor)
   - `display/window/size/viewport_width=1920`, `viewport_height=1080`
   - `rendering/renderer/rendering_method="gl_compatibility"` and `.mobile` likewise
3. In `export_presets.cfg` (Android preset):
   - `gradle_build/use_gradle_build=true`
   - `gradle_build/min_sdk="29"`, `target_sdk="33"`
   - `architectures/arm64-v8a=true`, others false
   - `package/unique_name` = your reverse-DNS package
   - `package/name` = the display name shown in BoardOS Settings → Sideloaded
4. Put a Piece Set Model `.tflite` in `assets/models/` (create the folder if it isn't there). The file just needs to be in that folder on disk — Godot won't *list* `.tflite` in its FileSystem dock (no importer, so no thumbnail and no `.import` file — that's expected, not an error), but the export's `include_filter` bundles it anyway. The SDK ships no model — the right one depends on which Piece Set your game uses. Download it from the live manifest at `https://dev.board.fun/downloads/models/manifest.json`: pick your Piece Set, fetch the entry's `url`, and save it into `assets/models/`. (An agent can do this with a plain HTTP GET; a human can use a browser. The sample app also fetches this manifest at runtime so its in-app picker shows what's available vs installed.)
5. Install the Custom Android Build Template: in Godot, `Project → Install Android Build Template` (extracts it into `android/build/`).
6. **One time**, edit `android/build/build.gradle`: inside `defaultConfig { aaptOptions { ... } }`, add `noCompress "pck", "sparsepck"` right after the `ignoreAssetsPattern` line. Godot's stock template doesn't set this, and without it the PCK is deflated inside the APK so cold boot takes ~2 minutes instead of a few seconds. You only do this once per project.
7. **Build and install** — see [Build & Deploy](#build--deploy). No build scripts are required: a human exports from Godot and installs over Board Connect; an agent uses the `board-connect` CLI.

The compiled `board.aar` ships with the addon under `addons/board_sdk/android/bin/debug/board.aar` — no separate build step.

## Public API Quick Reference

All modules hang off the `Board` autoload. Async methods return a request id (int); results land on typed signals; `await_*` helpers wrap the pattern with `await`.

| Domain | Module | Key entry points |
|---|---|---|
| Input | `Board.input` | `activate(model)`, `subscribe()`, signal `contacts_received` |
| UI input | `Board.ui_input` | `set_enabled(bool)` — fingers drive Control/Button UI; Pieces don't (on by default) |
| Session | `Board.session` | `get_players()`, `present_add_player(ai_type_indices)`, `present_replace_player(session_id, ai_type_indices)`, `reset_players()`, signals `players_changed`, `player_selector_finished` |
| Save | `Board.save` | `await_list()`, `await_create(...)`, `await_load(id)`, `update(...)`, `remove_players_from_save(id)`, `get_app_storage_info()` |
| Avatar | `Board.avatar` | `await_load_avatar(avatar_id)`, `await_default_avatar()`, `clear_cache()` |
| Pause | `Board.pause` | `set_context(ctx)`, `update_audio_tracks(...)`, signal `pause_result_received` |
| Application | `Board.application` | `quit()` |

Full reference: see the SDK README and [docs.dev.board.fun](https://docs.dev.board.fun).

## Critical Constraints

- **Touch coordinates** are display-pixel **Y-down**, with **no orientation flip**, and `glyph_id` is the raw integer. Don't add coordinate transforms — Godot's 2D viewport convention already matches the platform.
- **Use `glyph_id`, not `type_id`**, to distinguish pieces. `type_id` only tells you finger vs glyph (0 vs 1); the specific Piece is in `glyph_id`.
- **Pieces never touch the built-in UI.** On device the SDK swallows raw Android touches (a Piece's Glyph looks like an ordinary touch at the OS layer, so nothing else can tell it from a finger) and re-injects only *finger* contacts as synthetic screen-touch events. So `Button`/`Control`/`_gui_input` respond to fingers but never to Pieces — you don't need to guard your menus against Pieces. The trade-off: **finger-driven UI requires the touch detector to be running** (`Board.input.activate(model)` + `Board.input.subscribe()`); before a model is active, on-device UI receives no input. Activate early if you show menus before gameplay. Opt out with `Board.ui_input.set_enabled(false)` if you'd rather drive all UI from `contacts_received` yourself.
- **No piece-name helpers in the SDK.** Glyph IDs are integers. Your game owns whatever name table it needs (e.g., `const PAWN := 12`). The SDK never names pieces because Piece Set taxonomies are game-specific.
- **`load_data`** — not `load` (it shadows a GDScript built-in). There is no direct delete; see the next point.
- **No direct delete (matches Unity).** Detach players with `remove_players_from_save` or `remove_active_profile_from_save`; the OS deletes the save once no players remain associated with it.
- **Async pattern**: request_id (int) returned synchronously, result lands on a typed signal carrying the same id. Use the `await_*` helpers when you want await-style instead of explicit signal connect.
- **`set_context` omits missing keys.** Don't serialize empty defaults — empty `gameId` is rejected by the native side and silently disables the pause button.
- **`Board.application.quit()`** on-device, not `get_tree().quit()`. The SDK version notifies BoardOS so the user lands cleanly back in the launcher.
- **Always guard with `if not Board.is_on_device: return`** for every SDK call. Off-device (editor, desktop builds, simulator), `is_on_device` is `false` and modules return defaults.

## Common Patterns

### Tap-down vs hold (diffing per-frame snapshots)

There's only one touch signal: `contacts_received` delivers a full snapshot Array every inference frame. To get discrete edges (tap-down / tap-up, or piece-lifted), keep your own previous-frame map keyed by `contact_id` and diff it each frame:

```gdscript
var _prev := {}  # contact_id -> is_touched (last frame)

func _on_contacts(contacts: Array) -> void:
    var seen := {}
    for c in contacts:
        var contact_id := int(c.get("contact_id", 0))
        var is_touched := bool(c.get("is_touched", false))
        seen[contact_id] = is_touched
        var was_touched: bool = _prev.get(contact_id, false)
        if is_touched and not was_touched:
            # Rising edge — the user just pressed down on this piece
            _fire_weapon_at(int(c.get("glyph_id", 0)))
        elif was_touched and not is_touched:
            # Falling edge — tap-up / piece lifted
            pass
    _prev = seen
```

### Filtering by glyph ID

Hold the IDs your game cares about in a game-side constant table — never name pieces in the SDK layer:

```gdscript
const PIECE_PLAYER := 12
const PIECE_TARGET := 45

func _on_contacts(contacts: Array) -> void:
    for c in contacts:
        match c.glyph_id:
            PIECE_PLAYER: _track_player(c)
            PIECE_TARGET: _track_target(c)
```

### Player selector

The roster is OS-owned — a game can't silently add or remove who's playing. Players are added, removed, or replaced only through the OS selector overlay (`present_add_player()` / `present_replace_player()`) or cleared wholesale with `reset_players()`.

```gdscript
var rid := Board.session.present_add_player()
if rid >= 0:
    await Board.session.player_selector_finished
    var players := Board.session.get_players()
```

Both selector calls take an optional trailing `ai_type_indices: PackedInt32Array`. An empty array (the default) offers every AI type registered via `set_ai_player_types()`; a non-empty array restricts the selector's "Add AI" options to that subset.

```gdscript
# Only offer the "easy" and "medium" AI types (indices 0 and 1) in the selector.
Board.session.present_add_player(PackedInt32Array([0, 1]))

# Replace a specific seat, offering all registered AI types.
Board.session.present_replace_player(session_id)
```

To clear the whole roster:

```gdscript
Board.session.reset_players()
```

### Save game with await

```gdscript
var blob := PackedByteArray()
blob.resize(64)
var meta := await Board.save.await_create("Save 1", blob, 0, "1.0.0")  # BoardSaveMetadata or null
if meta == null:
    push_warning("save failed")
else:
    print("saved %s (%d bytes)" % [meta.id, meta.file_size])
```

### Player avatars

Avatars are loaded per-player, not by arbitrary id. Take a player's `avatar_id` off a `BoardPlayer` from `Board.session.get_players()` and pass it as an `int` (the field is a `String`). `await_load_avatar` returns a ready-to-display `ImageTexture` (already decoded), or `null` on failure / off-device. Textures are cached after the first load, and concurrent loads of the same id coalesce onto one fetch.

```gdscript
for player in Board.session.get_players():  # Array[BoardPlayer]
    var tex := await Board.avatar.await_load_avatar(int(player.avatar_id))
    if tex != null:
        $TextureRect.texture = tex
```

Use `Board.avatar.await_default_avatar()` for the default avatar (id 0), and `Board.avatar.clear_cache()` to drop the cached textures.

### App storage meter

`Board.save.get_app_storage_info()` is synchronous and returns a Dictionary with `total_storage`, `used_storage`, `remaining_storage` (all int bytes) and `usage_percentage` (float 0.0–1.0). Off-device it returns `{}`. Use it to render a storage meter or to pre-flight whether a save will fit before writing it.

```gdscript
var info := Board.save.get_app_storage_info()
if not info.is_empty():
    $StorageBar.value = info.usage_percentage * 100.0
    if info.remaining_storage < blob.size():
        push_warning("not enough room for this save")
```

### Pause overlay with a Restart custom button

> **Important**: Call `Board.pause.set_context(...)` during `_ready()` (before the user can tap the system menu button). The OS owns the system menu button — the plugin shows it on init/resume and hides it on pause/stop/destroy automatically across the activity lifecycle, so there's no game-side call to toggle it. But without an active context, tapping the button produces no visible response — there's nothing for the OS to display. The context is what gives the button something to open.

```gdscript
func _ready() -> void:
    if not Board.is_on_device:
        return
    Board.initialize(APP_ID)

    Board.pause.set_context({
        "game_name": "My Game",
        "offer_save_option": true,
        "custom_buttons": [{ "id": "restart", "title": "Restart", "icon": Board.pause.ICON_CIRCULAR_ARROW }],
    })
    Board.pause.pause_result_received.connect(_on_pause_result)


func _on_pause_result(result: BoardPauseResult) -> void:
    match result.action:
        Board.pause.ACTION_RESUME:
            pass  # user resumed
        Board.pause.ACTION_QUIT:
            Board.application.quit()
        Board.pause.ACTION_CUSTOM_BUTTON:
            if result.custom_button_id == "restart":
                get_tree().reload_current_scene.call_deferred()
```

### Off-device development guard

```gdscript
if not Board.is_on_device:
    # Synthetic input for desktop dev — let the user pretend with the mouse.
    _wire_mouse_fallback()
    return
```

## Build & Deploy

No build scripts are required. Build the APK with Godot's own export, then install it on the Board. (Full walkthrough: [docs.dev.board.fun](https://docs.dev.board.fun).)

**Build** — in the Godot editor, `Project → Export Project… → Android`. With `gradle_build/use_gradle_build=true` set (checklist step 3), this runs the Gradle build and writes a `.apk` signed with the debug keystore. Headless equivalent: `godot --headless --export-debug "Android" <out>.apk`. The export bundles the addon's `board.aar` (so `libboard.so` is present for the install gate) and the Piece Set Model in the PCK — a vanilla export Just Works, no asset staging.

Use `--export-debug` (or the editor's debug export) while iterating; build a **release** export (`--export-release`) for distribution — it's far smaller, since a debug build ships the unstripped Godot engine library (~75 MB on its own).

**Install (human)** — open the Board Connect web UI in a browser (the Board shows its address under `Settings → System`) and drag the `.apk` onto it. It installs; launch it from the Library.

**Install (agent)** — use the **`board-connect` CLI**, the agent-facing counterpart to the Board Connect web UI (no ADB, no scripts). Install it once from `dev.board.fun/connect/install`, then:

```sh
board-connect pair <host>                       # tap Approve on the device (once)
board-connect install <host> your-game.apk      # type auto-detected
board-connect launch <host> your.package.name
board-connect logs <host> your.package.name     # one-shot log dump
board-connect screenshot --out shot.png <host>
```

`<host>` is the Board's `ip` or `ip:port` (default `:8843`), shown under `Settings → System`; `board-connect ls` discovers Boards on your LAN. The pair token is cached and reused.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| BoardOS Settings → Sideloaded shows `godot-project-name` instead of the game name | `package/name` isn't set in the Android export preset (checklist step 3). Godot's Export Project writes the name from there; the placeholder only ships if you drive the build template via raw Gradle without setting it. |
| `Couldn't load file 'res://project.binary'` at runtime | The PCK isn't at `assets/assets.sparsepck` inside the APK. Godot's Export Project places it correctly; this only happens if you assemble the APK via raw Gradle without staging the PCK there. |
| The Board rejects the APK with "this APK is not built with Board SDK" | The bundled `board.aar` is missing `lib/arm64-v8a/libboard.so`. Re-copy `addons/board_sdk/` from a clean SDK release; if it persists, report it at board.fun. |
| Pause button on the OS overlay does nothing when tapped | `set_context` was called with a key set to an empty string. Omit the key instead — `JSON.stringify(undefined)` semantics. |
| `is_session_ready()` returns false forever | Services haven't bound yet. Poll `Board.session.are_services_ready()` first, or wait a frame after `Board.initialize()`. |
| Cold boot takes >2 minutes | The PCK is being deflated inside the APK. Add `noCompress "pck", "sparsepck"` to `android/build/build.gradle`'s `aaptOptions` block (setup checklist step 6); verify the line is present. |
| `is_ready()` undefined error | Method was renamed to `is_session_ready()` in v1.0. Update callers. |

## What NOT to Do

- Don't call `get_tree().quit()` on-device. Use `Board.application.quit()`.
- Don't add coordinate transforms in your input handler. Coordinates are already display-pixel Y-down + screen-CW positive.
- Don't subscribe to `Board.input` signals before `Board.initialize()` returns.
- Don't name methods `load` or `delete` on classes you also expose as autoloads — they shadow GDScript built-ins. (The SDK uses `load_data` for this reason, and exposes no direct delete.)
- Don't bake piece names into the SDK layer or any shared library. Glyph taxonomies belong to the game.
- Don't serialize empty defaults into `set_context`. Omit absent keys entirely.

## Where to Find More

- SDK README: `<sdk>/README.md`
- Full developer docs: [docs.dev.board.fun](https://docs.dev.board.fun)
- Sample app: `<sdk>/sample/`
- Changelog: `<sdk>/CHANGELOG.md`
- Bootstrap skill: `<sdk>/skills/bootstrap-board-godot-game/`
