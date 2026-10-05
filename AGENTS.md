# Chess 4 Board — Workspace Rules & Conventions

## 1. Canonical Root Files (No Duplicates)
The following project-wide files must exist **exclusively** in the repository root (`/Users/adamlaster/Development/BoardGames/Chess4Board/`):
- `README.md` — Project overview, architecture, quick-start build instructions, controls reference, and app catalog.
- `BUILD_SEQUENCE.md` — Detailed 4-step Gradle AAR -> Godot CLI export -> `board-connect` deployment pipeline.
- `PROJECT_HISTORY.md` — Complete chronological engineering log, architectural decisions, and feature roadmap.
- `build_and_deploy.sh` — Single automated CLI build and deployment script.

**Do NOT** create or sync duplicate copies of these files inside `chess-4-board/`, `godot-webview/`, or `~/Documents/AI_Markdown/`.

## 2. Keep Root Documentation Up to Date
Whenever you add or modify features, web apps/categories, menu controls, or build/deployment behavior:
1. Update `PROJECT_HISTORY.md` with the new phase/changes and current controls/app reference.
2. Update `README.md` and `BUILD_SEQUENCE.md` if any user-facing features, app lists, controls, or build steps changed.

## 3. Build & Output Hygiene
- **Out-of-Tree APK Output:** Always export `Chess4Board.apk` to `/Users/adamlaster/Development/BoardGames/output/Chess4Board.apk` (never inside the git repository).
- **Clean Godot Resource Tree:** Keep `chess-4-board/` free of unused test scripts, duplicate icons, or unused `.tflite` models (`Chess 4 Board` uses native touch passthrough via `GodotWebView.prepareBoardTouchPassthrough()`).
