# Chess 4 Board (`chess-4-board` & `godot-webview`) — Project & Session Lifecycle Log

This document tracks the complete architecture, chronological evolution, engineering decisions, and future roadmap for **Chess 4 Board** (`com.lastersoft.chess4board`) running on the **Board** digital tabletop device.

---

## 1. Project Overview & Architecture

**Chess 4 Board** is a custom-engineered web application hub and tabletop gaming portal built for the **Board** hardware device (an Android-based large-format touch tabletop display).

Because the Board OS enforces native SDK validation (`libboard.so` / `libnativeBoardSDK.so`) on all installed APKs, standalone Android APKs cannot be sideloaded directly via `board-connect`. Instead, **Chess 4 Board** wraps a hardware-accelerated Android `WebView` plugin (`GodotWebView`) inside a Godot host application (`chess-4-board`) that includes the Board SDK native libraries.

### Repository Layout
| Component | Path | Role |
|---|---|---|
| **Root Workspace (`Chess4Board`)** | `/Users/adamlaster/Development/BoardGames/Chess4Board` | Top-level repository root containing both `chess-4-board` and `godot-webview`. |
| **Host Godot App (`chess-4-board`)** | `/Users/adamlaster/Development/BoardGames/Chess4Board/chess-4-board` | Godot project, Board SDK integration, 3-second custom splash screen (`root.gd`), adaptive launcher icons, and APK export configuration (`export_presets.cfg`). |
| **Native Android Plugin (`godot-webview`)** | `/Users/adamlaster/Development/BoardGames/Chess4Board/godot-webview` | Custom Java Android AAR library (`GodotWebView.java`) providing the Chromium `WebView`, categorized app launcher, back/zoom/refresh/UA/rotate controls, HTML5 fullscreen video handler, and DRM permission bridge. |
| **Automated Build & Deploy Pipeline** | `/Users/adamlaster/Development/BoardGames/Chess4Board/build_and_deploy.sh` | Single-command root CLI script that compiles Debug/Release AARs via Gradle, copies them into `addons/webview/`, exports `Chess4Board.apk` headlessly to `/Users/adamlaster/Development/BoardGames/output/Chess4Board.apk`, and deploys/launches on the Board device via `board-connect`. |
| **APK Output Directory** | `/Users/adamlaster/Development/BoardGames/output` | Out-of-tree build output directory where `Chess4Board.apk` is exported and deployed from (keeping large APK binaries outside the git repository). |
| **Root Documentation** | `/Users/adamlaster/Development/BoardGames/Chess4Board/` | Single canonical location for `README.md`, `BUILD_SEQUENCE.md`, and `PROJECT_HISTORY.md`. |

---

## 2. Complete Session & Project Chronology

### Phase 1: Codebase Inspection, Missing Imports & Full CLI Build Automation
1. **Initial `GodotWebView.java` Audit:**
   - Inspected `GodotWebView.java` and resolved missing Android/Java imports (`ColorStateList`, `Configuration`, `Typeface`, `MotionEvent`, `ViewConfiguration`, `ProgressBar`, `SignalInfo`, `HashSet`, `Set`) so the plugin could compile cleanly under Gradle + JDK 17.
2. **End-to-End CLI Pipeline (`build_and_deploy.sh`):**
   - Replaced manual Android Studio + Godot IDE export steps with a 100% automated 4-step CLI workflow documented in `BUILD_SEQUENCE.md`:
     1. `./gradlew --no-build-cache clean assemble` in `godot-webview/GodotWebView`
     2. Copy `GodotWebView-debug.aar` & `GodotWebView-release.aar` to `chess-4-board/addons/webview/`
     3. `/Applications/Godot.app/Contents/MacOS/Godot --headless --path ... --export-debug "Android" ./Chess4Board.apk`
     4. `board-connect install Chess4Board.apk --launch` (uploading over LAN to `10.0.0.65:8843`)

---

### Phase 2: Floating Menu UX Overhaul & Tabletop Ergonomics
1. **Outside-Tap Scrim Dismissal:**
   - Added a full-screen translucent backdrop (`scrimView`, `#4D000000`) behind the menu card so tapping anywhere outside the menu cleanly dismisses it.
2. **Draggable Floating Action Button (`☰`) with Screen Clamping:**
   - Collapsed the multi-button overlay into a single `58dp` circular floating `☰` button (`floatingButton`).
   - Implemented touch-slop detection (`ViewConfiguration.getScaledTouchSlop()`) to distinguish taps from drags, clamping coordinates within screen margins.
3. **Idle Auto-Fade:**
   - Added a 4-second inactivity timer (`idleHandler` / `idleFadeRunnable`) that fades the floating `☰` button to `35%` opacity during gameplay and restores `100%` opacity on touch.
4. **Top Loading Progress Bar:**
   - Added a `4dp` green (`#43A047`) horizontal `ProgressBar` anchored to the top of the viewport (`WebChromeClient.onProgressChanged`).
5. **Tactile "Slide to Exit" Safety Slider:**
   - Iterated from a bottom-row `✕` button to an upper-left corner button, and finally settled on a **Slide to Exit (`✕ Slide to Exit ❯❯❯`)** track at the bottom of the menu card.
   - Requires sliding the red thumb past `80%` of the track width to emit `quit_app_requested`, preventing accidental exits during tabletop play without requiring a two-step confirmation modal.
6. **Orientation Rotation Pinning (`90°`):**
   - Fixed an issue where rotating between Portrait and Landscape left the floating button stranded in the middle of the screen.
   - Added `layout.addOnLayoutChangeListener` and post-rotation snapping so the `☰` button always re-pins cleanly to the bottom-right corner on rotation.

---

### Phase 3: Refresh Controls, Custom Splash Screen & Launcher Branding
1. **Pull-to-Refresh vs. Menu Refresh Button (`↺`):**
   - Experimented with Android's `SwipeRefreshLayout`, which caused gesture conflicts with vertical scrolling and tabletop board dragging.
   - Removed `SwipeRefreshLayout` (and removed the `androidx.swiperefreshlayout` Gradle dependency completely) in favor of a dedicated **`↺`** refresh button in the control row.
   - Updated the rotate button label to bold **`90°`** so it is immediately distinguishable from **`↺`**.
2. **Custom Splash Screen & 3-Second Hold:**
   - Replaced default Godot boot images with the custom photo splash screen (`splash.png`) configured in `project.godot` and `chess.tscn` (`root.gd`), holding the splash image for 3.0 seconds before launching `GodotWebView`.
3. **Custom Pawn App Icon:**
   - Generated Android adaptive foreground/background icons (`icon.png`, `icon_192.png`, `icon_432.png`, `icon_background_432.png`) using the Dark Pawn emblem on a clean white background.

---

### Phase 4: Multi-Game Expansion, WebView Performance & Sideload Discovery
1. **Root Chess Suite:**
   - Configured the primary root menu with 4 core chess platforms:
     - `♟ Chess.com` (`https://www.chess.com`)
     - `♟ ChessKids.com` (`https://www.chesskids.com`)
     - `♟ Lichess` (`https://lichess.org/analysis`)
     - `♟ ChessReps` (`https://chessreps.com`)
   - Hid the legacy Godot debug UI nodes inside `chess.tscn`.
2. **Tabletop Touch Games Curation:**
   - Tested multiple web games for large-screen multi-touch suitability.
   - Added **Colonist.io (Catan)**, **Dots & Boxes**, **PBS Kids**, **247 Backgammon**, **247 Checkers**, and the full **247 Games** portal (`https://www.247games.com`).
   - Removed Euchre (`cardgames.io`) after testing showed poor tabletop UX.
3. **WebView Hardware Acceleration & Rendering Tuning:**
   - Enabled `View.LAYER_TYPE_HARDWARE` on the `WebView`.
   - Enabled `settings.setOffscreenPreRaster(true)` (API 23+) to prevent white flashes during scrolling/zooming.
   - Disabled overscroll glow (`OVER_SCROLL_NEVER`) and scrollbars.
   - Flushed `CookieManager` on `onPageFinished` so logins and game states persist reliably across sessions.
4. **Board OS Native SDK Sideload Discovery:**
   - Attempted to sideload a standalone open-source Checkers APK via `board-connect install`, which failed with:
     `[validation_failed] missing Board SDK native library (expected lib/<abi>/libboard.so or libnativeBoardSDK.so)`.
   - Confirmed that hosting web apps and games inside `Chess4Board.apk` (which bundles the Board SDK native library) is the ideal architectural path for expanding functionality on the device.

---

### Phase 5: Video Streaming Hub, User-Agent Spoofing & HTML5 Fullscreen
1. **Video Streaming Services & DRM Support:**
   - Added **YouTube** (`https://www.youtube.com`), **Peacock** (`https://www.peacocktv.com`), and **Fox One** (`https://www.fox.com`).
   - Implemented `WebChromeClient.onPermissionRequest` to automatically grant `PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID` for Encrypted Media Extensions (EME / Widevine DRM).
   - Enabled `settings.setMediaPlaybackRequiresUserGesture(false)`.
2. **Native App Intent Blocking:**
   - Updated `shouldOverrideUrlLoading` to intercept non-HTTP/HTTPS schemes (`intent://`, `vnd.youtube://`, `market://`), extract `browser_fallback_url` when available, and block native app launch errors (`ERR_UNKNOWN_URL_SCHEME`).
3. **On-Demand Mobile / Desktop User-Agent Toggle (`📱` / `🖥`):**
   - Added a toggle button in the controls row (`[ ⬅ ] [ － ] [ ＋ ] [ ↺ ] [ 📱/🖥 ] [ 90° ] [ ⬇ ]`).
   - Defaults to **Mobile Mode (`📱`)** and automatically reverts to **Mobile Mode** whenever switching sites via `navigateToSite()`.
   - Handles YouTube's sticky `PREF` cookie by appending `?app=desktop` when toggling to Desktop (`🖥`) and `?app=mobile` when toggling or resetting to Mobile (`📱`).
4. **HTML5 Fullscreen Video Support:**
   - Implemented `onShowCustomView` and `onHideCustomView` in `WebChromeClient` (along with `exitCustomFullscreen()`) to attach/detach Chromium's fullscreen video surface inside `layout` while keeping `floatingButton`, `scrimView`, and `menuCard` layered on top.

---

### Phase 6: Consolidated Categorized "Extra Apps" Menu (`MLB.TV` & `Google`) & Back Navigation (`⬅`)
1. **Consolidated Categorized Menu (`🗂️ Extra Apps`):**
   - Replaced the separate top-level `Extra Games` and `Video` buttons on the root menu card with a single collapsible **`🗂️  Extra Apps (11)  ▾`** menu button backed by a structured `List<CategoryEntry>` (`EXTRA_CATEGORIES`).
   - Inside `Extra Apps`, categories render as sleek accordion headers that expand/collapse their apps on tap:
     - **`🎲  Games (6)`**: Colonist.io (Catan), Dots & Boxes, PBS Kids, 247 Backgammon, 247 Checkers, 247 Games (All)
     - **`📺  Video (4)`**: YouTube, Peacock, Fox One, **MLB.TV** (`https://www.mlb.com/tv`)
     - **`🌐  Web (1)`**: **Google** (`https://www.google.com`)
   - Implemented an adaptive height cap (`onMeasure` `AT_MOST` `240dp`) on `extraAppsScrollView` so the menu stays compact when categories are collapsed and scrolls smoothly when large categories are expanded.
2. **Back Navigation Button (`⬅`):**
   - Added a **`⬅`** Back button at the start of the controls row (`[ ⬅ ] [ － ] [ ＋ ] [ ↺ ] [ 📱/🖥 ] [ 90° ] [ ⬇ ]`).
   - Automatically dims (`35%` alpha) when `webView.canGoBack()` is false; navigates back in history (or exits fullscreen video if active) when tapped.
3. **Immediate "Closing..." Slide-to-Exit Feedback & Fast Shutdown:**
   - As soon as the slider reaches `92%` during a drag (or is released past `80%`), the thumb locks at the right end with a **`✓`** icon, the track turns solid red (`#C62828`), the label displays **`Closing...`** in bold white, the scrim darkens to `90%` black, and `webView.onPause()` halts media playback immediately.
   - Restored `Engine.max_fps = 60` inside `_on_quit_app_requested()` in `root.gd` so Godot processes `get_tree().quit()` immediately without waiting up to 1 second on the `Engine.max_fps = 1` background throttle.

---

### Phase 7: Package Rename, 2x Tabletop Menu Scaling, Custom Photo App Icon & Board SDK Integration Fix
1. **Package Rename (`com.lastersoft.godotwebview`):**
   - Migrated the entire Android plugin package from `com.bsmx.godotwebview` to `com.lastersoft.godotwebview` across `GodotWebView.java`, `build.gradle`, `AndroidManifest.xml`, and `plugin.cfg`.
   - Added a `JavaCompile` exclusion rule (`exclude 'com/bsmx/**'`) in `build.gradle` to guard against stale IDE tab re-saves.
2. **2x Opened Menu Card (`MENU_SCALE = 2.0f`) & Tighter Slide-to-Exit Threshold:**
   - Doubled the dimensions and typography of the opened `menuCard` and all internal buttons/controls (`640dp` wide card, `88dp` site buttons, `74dp` circular controls, `92dp` slide track) for effortless tabletop visibility, while keeping the closed floating `☰` button at `58dp`.
   - Tightened the Slide-to-Exit trigger threshold (`progress >= 0.985f` on drag, `releaseProgress >= 0.95f` on release) to match the wider 2x track.
3. **App Icon Restoration (Dark Pawn):**
   - Tested a custom photo launcher icon (`icon.png`, `icon_192.png`, `icon_432.png`), then restored the crisp **Dark Pawn on white** adaptive icons (`icon.png`, `icon_192.png`, `icon_432.png`, `icon_background_432.png`).
4. **Board SDK (`https://docs.dev.board.fun/`) Touch Passthrough & "Exit to Library" Fix:**
   - **Touch Passthrough:** Configured `BoardNativePlugin.setSwallowSystemTouches(false)` and `BoardNativePlugin.nativeLibLoaded = false` in `GodotWebView.prepareBoardTouchPassthrough()` so `Board.initialize(...)` binds to `SystemOverlayService` without attaching `touchSwallower` or starting `RawDataGlyphDetector` (preserving 100% standard Android touch in the `WebView`).
   - **Async Pause Context Registration:** Fixed a race condition where `Board.pause.set_context(...)` was called before `SystemOverlayService` finished binding (`are_services_ready()`), ensuring the Board pause callback is always registered.
   - **Direct Java-Side "Exit to Library" Handler:** Hooked `PauseResultCallbackImpl` on the Java side so tapping **"Exit to Library"** on the Board's system menu immediately calls `SessionManagerBridge.terminateApplication()` (`ISystemOverlayService.terminateApp()`) without waiting on Godot's 1-FPS throttled main loop.
   - **Hidden Custom Slide-to-Exit Bar:** Set `slideTrack.setVisibility(View.GONE)` now that the native Board system menu handles exiting cleanly.

---

### Phase 8: Board System "Web Menu" Button, Desktop Default UA, 4-Way Rotation & Expanded Web Apps
1. **Board System Menu Custom "Web Menu" Button & Removal of Floating `☰` Button:**
   - Added a custom button (`{ "id": "open_menu", "title": "Web Menu", "icon": Board.pause.ICON_SQUARE }`) to the Board OS pause overlay via `Board.pause.set_context(...)` in `root.gd` (and fallback registration in `GodotWebView.ensureBoardPauseContextRegistered()`).
   - Hooked `PauseResultCallbackImpl.getCustomButtonId()` alongside `getActionType()` in `GodotWebView.hookBoardPauseListener()` so tapping **"Web Menu"** on the Board system menu immediately dismisses the Board overlay and opens our `menuCard` centered on screen (`runOnUiThread(this::showMenu)`).
   - Hid the custom floating `☰` button (`floatingButton.setVisibility(View.GONE)`) and updated `repositionMenuCard()` to center `menuCard` on the display.
2. **Desktop User-Agent by Default + 3-Second Long-Press Default Saver & Ack Dialog:**
   - Changed the default User-Agent mode to **Desktop (`🖥`)**, persisted in `SharedPreferences` (`chess4board_prefs` / `default_desktop_mode`).
   - **Short tap on `🖥` / `📱`:** Toggles User-Agent for the current site only (reverting to the saved default when navigating to another site).
   - **3-second long-press on `🖥` / `📱`:** Toggles and saves the new global default User-Agent in `SharedPreferences` and pops a dark-themed confirmation modal (`showDefaultUaAckDialog`).
3. **4-Way `90°` Tabletop Orientation Cycle + Long-Press Reset:**
   - Updated the `90°` button (`ORIENTATION_CYCLE`) to step clockwise through all 4 tabletop orientations: `SCREEN_ORIENTATION_LANDSCAPE` → `SCREEN_ORIENTATION_PORTRAIT` → `SCREEN_ORIENTATION_REVERSE_LANDSCAPE` → `SCREEN_ORIENTATION_REVERSE_PORTRAIT`.
   - **Long-pressing `90°`** immediately resets the screen back to the default `SCREEN_ORIENTATION_LANDSCAPE` (index `0`) with no dialog required.
4. **Expanded Web Category (`Google Photos`, `Google Maps`, `Reddit`, `Wikipedia`, `Weather`) & Streaming Additions (`Disney+`, `Prime Video`):**
   - Expanded `Extra Apps` to **18 apps** across `Games (6)`, `Video (6)`, and `Web (6)`.

---

### Phase 9: Godot Resource Cleanup & Canonical Root Script / Documentation
1. **Removed Unused Godot Resources in `chess-4-board`:**
   - Deleted legacy test scripts and `.uid` sidecars (`app.gd`, `button_2.gd`, `button_3.gd`, `button_test.gd`, `panel_container.gd`, `v_box_container.gd`).
   - Removed unused icon and import files (`icon.svg`, `icon_square.png`, `splash_download.png.import`) and orphaned `.godot/imported/` cache entries.
   - Removed unused `assets/models/model.tflite` (~952 KB), as `Chess 4 Board` uses touch passthrough rather than piece glyph detection.
2. **Consolidated Single Canonical `build_and_deploy.sh`, `BUILD_SEQUENCE.md`, and `PROJECT_HISTORY.md` in Root (`/Users/adamlaster/Development/BoardGames/Chess4Board/`):**
   - Moved `build_and_deploy.sh` to the repository root (`/Users/adamlaster/Development/BoardGames/Chess4Board/build_and_deploy.sh`) and removed duplicate scripts from `chess-4-board/` and `godot-webview/`.
   - Consolidated `BUILD_SEQUENCE.md` and `PROJECT_HISTORY.md` exclusively in the repository root and removed all duplicate copies in `chess-4-board/`, `godot-webview/`, and `Documents/AI_Markdown/`.

---

## 3. Current Menu & Controls Reference

### Opening & Exiting via Board System Menu
* **Board System Menu Button (Hardware/OS Overlay):**
  * **Resume:** Returns to the current web app
  * **Web Menu:** Opens the centered **Chess 4 Board** `menuCard` overlay
  * **Exit to Library:** Terminates the app cleanly via `SessionManagerBridge.terminateApplication()` and returns to the Board OS Library

### Centered Web Menu Card (`menuCard`)
* **Primary Chess Sites:**
  * `♟  Chess.com` — `https://www.chess.com`
  * `♟  ChessKids.com` — `https://www.chesskids.com`
  * `♟  Lichess` — `https://lichess.org/analysis`
  * `♟  ChessReps` — `https://chessreps.com`
* **`🗂️  Extra Apps (18)  ▾`** *(Collapsible Categorized Accordion)*:
  * **`🎲  Games (6)  ▾`**
    * `🐑  Colonist.io (Catan)` — `https://colonist.io`
    * `✏️  Dots & Boxes` — `https://gametable.org/games/dots-and-boxes/`
    * `🎈  PBS Kids` — `https://pbskids.org`
    * `🎲  247 Backgammon` — `https://www.247backgammon.org`
    * `🔴  247 Checkers` — `https://www.247checkers.com/`
    * `🌐  247 Games (All)` — `https://www.247games.com`
  * **`📺  Video (6)  ▾`**
    * `▶️  YouTube` — `https://www.youtube.com`
    * `🦚  Peacock` — `https://www.peacocktv.com`
    * `🦊  Fox One` — `https://www.fox.com`
    * `⚾  MLB.TV` — `https://www.mlb.com/tv`
    * `🏰  Disney+` — `https://www.disneyplus.com`
    * `📦  Prime Video` — `https://www.amazon.com/gp/video/storefront`
  * **`🌐  Web (6)  ▾`**
    * `🔍  Google` — `https://www.google.com`
    * `🖼️  Google Photos` — `https://photos.google.com`
    * `🗺️  Google Maps` — `https://www.google.com/maps`
    * `👽  Reddit` — `https://www.reddit.com`
    * `📖  Wikipedia` — `https://www.wikipedia.org`
    * `⛅  Weather` — `https://weather.com`
* **Control Row (`[ ⬅ ] [ － ] [ ＋ ] [ ↺ ] [ 🖥/📱 ] [ 90° ] [ ⬇ ]`):**
  * **`⬅`**: Navigate back in `WebView` history (or exit fullscreen video); dims when no back history exists
  * **`－` / `＋`**: Step zoom (`75%`, `100%`, `125%`, `150%`, `200%`) via `setTextZoom` + CSS `zoom`
  * **`↺`**: Reload current page
  * **`🖥` / `📱`**: Short tap toggles Desktop vs. Mobile User-Agent for current site; **3-second hold** toggles & saves the global default User-Agent (with confirmation dialog)
  * **`90°`**: Short tap cycles clockwise through all 4 orientations (`Landscape` → `Portrait` → `Reverse Landscape` → `Reverse Portrait`); **long-press** resets to default `Landscape`
  * **`⬇`**: Close menu overlay

---

## 4. Future Roadmap & Planned Features

### 📌 Planned Feature: Native On-Device URL & Category Manager
* **Goal:** Allow adding, editing, and removing custom URLs and custom Categories directly from the Board screen at runtime without modifying Java code or rebuilding the APK.
* **Proposed Technical Design:**
  1. **Data Persistence (`SharedPreferences` JSON Store):**
     - Seed `SharedPreferences` (`chess4board_custom_apps`) with the default `EXTRA_CATEGORIES` list on first launch.
     - Deserialize `List<CategoryEntry>` dynamically via `org.json.JSONArray` / `JSONObject` (built into the Android SDK with zero external dependencies) whenever the menu builds.
  2. **Native Android Dialog UI (`＋ Add App / Category`):**
     - Add a **`＋ Add Link`** button inside the `Extra Apps` menu (or controls area).
     - Trigger a native Android `AlertDialog` styled in dark mode containing:
       - **App Name** (`EditText`, e.g., `"ESPN"`)
       - **URL** (`EditText` with `InputType.TYPE_TEXT_VARIATION_URI`, auto-prefixing `https://` if omitted)
       - **Category Selector** (`Spinner` or pill list of existing categories + `"＋ New Category..."` option with a category name `EditText`)
       - **Default User-Agent Preference (Optional):** Per-site flag to remember whether a site prefers Mobile (`📱`) or Desktop (`🖥`) mode.
  3. **Management / Deletion:**
     - Long-pressing any custom app or category button opens a quick native confirmation dialog to **Edit** or **Delete** the entry, or **Reset to Defaults**.