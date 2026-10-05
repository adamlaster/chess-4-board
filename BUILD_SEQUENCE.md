# Chess 4 Board — Build & Deployment Pipeline

This document details the complete build, packaging, and deployment pipeline for **Chess 4 Board** (`com.lastersoft.chess4board`) running on the **Board** digital tabletop device.

The project uses a custom Android native plugin (`com.lastersoft.godotwebview.GodotWebView`) integrated with the Board OS SDK—featuring a Board system menu "Chess 4 Board Menu" trigger, 2x tabletop-scaled centered launcher card, Desktop/Mobile User-Agent switching, 4-way orientation cycling, zoom controls, HTML5 fullscreen/DRM video playback, and native multi-touch pass-through.

---

## ⚡ Quick Start: One-Step Automated Pipeline

A unified build script handles the entire 4-step sequence automatically:

```bash
cd /Users/adamlaster/Development/BoardGames/Chess4Board
./build_and_deploy.sh
```

### Script Options:
* **Full pipeline (default):** Recompiles Android library, copies AARs, exports Godot APK to `/Users/adamlaster/Development/BoardGames/output/Chess4Board.apk`, and installs/launches on Board:
  ```bash
  ./build_and_deploy.sh
  ```
* **Godot-only updates (skip Java/AAR compilation):**
  ```bash
  ./build_and_deploy.sh --skip-aar
  ```
* **Build without deploying:**
  ```bash
  ./build_and_deploy.sh --no-deploy
  ```

---

## 📋 Detailed 4-Step Pipeline Breakdown

### Step 1: Build Android WebView Plugin (AAR)
Compiles both debug and release Android library binaries containing our custom `GodotWebView` Java implementation (`com.lastersoft.godotwebview`) and Android dependencies.

* **Working Directory:** `/Users/adamlaster/Development/BoardGames/Chess4Board/godot-webview/GodotWebView`
* **Command:**
  ```bash
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
  ./gradlew --no-build-cache clean assemble
  ```
* **Outputs:**
  * `GodotWebView/GodotWebView/build/outputs/aar/GodotWebView-debug.aar`
  * `GodotWebView/GodotWebView/build/outputs/aar/GodotWebView-release.aar`

---

### Step 2: Copy AARs to Chess 4 Board Project
Copies the updated native AAR binaries directly into the game's `addons/webview` directory so Godot packages them into the Android export template.

* **Source Directory:** `/Users/adamlaster/Development/BoardGames/Chess4Board/godot-webview/GodotWebView/GodotWebView/build/outputs/aar`
* **Destination Directory:** `/Users/adamlaster/Development/BoardGames/Chess4Board/chess-4-board/addons/webview`
* **Command:**
  ```bash
  cp /Users/adamlaster/Development/BoardGames/Chess4Board/godot-webview/GodotWebView/GodotWebView/build/outputs/aar/GodotWebView-debug.aar /Users/adamlaster/Development/BoardGames/Chess4Board/chess-4-board/addons/webview/
  cp /Users/adamlaster/Development/BoardGames/Chess4Board/godot-webview/GodotWebView/GodotWebView/build/outputs/aar/GodotWebView-release.aar /Users/adamlaster/Development/BoardGames/Chess4Board/chess-4-board/addons/webview/
  ```

---

### Step 3: Export Android APK via Godot CLI
Performs a headless compilation and packaging of `chess-4-board` into an Android APK using the Android Gradle build template configured in `export_presets.cfg`.

* **Project Directory:** `/Users/adamlaster/Development/BoardGames/Chess4Board/chess-4-board`
* **Command:**
  ```bash
  export ANDROID_HOME="/Users/adamlaster/Library/Android/sdk"
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
  mkdir -p /Users/adamlaster/Development/BoardGames/output
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/adamlaster/Development/BoardGames/Chess4Board/chess-4-board --export-debug "Android" /Users/adamlaster/Development/BoardGames/output/Chess4Board.apk
  ```
* **Output:** `/Users/adamlaster/Development/BoardGames/output/Chess4Board.apk` (stored out-of-tree so large APK binaries stay outside the git repository)

---

### Step 4: Install and Launch APK on Board Device
Uploads and installs `Chess4Board.apk` to the target Board device over LAN, then immediately launches the app.

* **Working Directory:** `/Users/adamlaster/Development/BoardGames/output`
* **Command:**
  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  board-connect install /Users/adamlaster/Development/BoardGames/output/Chess4Board.apk --launch
  ```
* **Output:** Real-time upload progress bar and confirmation from the `board-connect` CLI tool.

---

## 🛠️ Environment & Tool Requirements

| Tool | Resolved Path | Purpose |
|---|---|---|
| **JDK 17** | `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home` | Compiles Gradle AAR and Android APK |
| **Android SDK** | `/Users/adamlaster/Library/Android/sdk` | Build tools, platform tools (`adb`), target API 34 |
| **Godot Engine** | `/Applications/Godot.app/Contents/MacOS/Godot` | Headless game engine exporter |
| **Board Connect** | `~/.local/bin/board-connect` | Board device deployment & launch tool |
| **Board Device Config** | `~/.config/board-connect/config.json` | IP: `10.0.0.65:8843` |

---

## 🎮 Active Sites & Categorized Extra Apps Configuration

### Root Chess Menu
* ♟ **Chess.com**: `https://www.chess.com`
* ♟ **ChessKids.com**: `https://www.chesskids.com`
* ♟ **Lichess**: `https://lichess.org/analysis`
* ♟ **ChessReps**: `https://chessreps.com`

### 🗂️ Extra Apps Menu (18 Apps Across 3 Categories)
* **🎲 Games (6)**
  * 🐑 **Colonist.io (Catan)**: `https://colonist.io`
  * ✏️ **Dots & Boxes**: `https://gametable.org/games/dots-and-boxes/`
  * 🎈 **PBS Kids**: `https://pbskids.org`
  * 🎲 **247 Backgammon**: `https://www.247backgammon.org`
  * 🔴 **247 Checkers**: `https://www.247checkers.com/`
  * 🌐 **247 Games (All)**: `https://www.247games.com`
* **📺 Video (6)**
  * ▶️ **YouTube**: `https://www.youtube.com`
  * 🦚 **Peacock**: `https://www.peacocktv.com`
  * 🦊 **Fox One**: `https://www.fox.com`
  * ⚾ **MLB.TV**: `https://www.mlb.com/tv`
  * 🏰 **Disney+**: `https://www.disneyplus.com`
  * 📦 **Prime Video**: `https://www.amazon.com/gp/video/storefront`
* **🌐 Web (6)**
  * 🔍 **Google**: `https://www.google.com`
  * 🖼️ **Google Photos**: `https://photos.google.com`
  * 🗺️ **Google Maps**: `https://www.google.com/maps`
  * 👽 **Reddit**: `https://www.reddit.com`
  * 📖 **Wikipedia**: `https://www.wikipedia.org`
  * ⛅ **Weather**: `https://weather.com`

> **Note:** See [`PROJECT_HISTORY.md`](./PROJECT_HISTORY.md) in the root directory for the complete chronological history of the project and the roadmap for adding native on-device URL & category management.
