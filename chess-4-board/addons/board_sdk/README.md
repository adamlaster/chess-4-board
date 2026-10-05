# Board SDK (Godot)

Build games for **Board**, the tabletop gaming platform with physical piece
tracking, using **Godot 4.6+**.

The SDK ships as a drop-in addon. Game code uses the `Board` autoload to access
touch and piece input, multiplayer sessions, save games, avatars, the system
pause overlay, and application-lifecycle control. The compiled `board.aar`
ships pre-built under `android/bin/{debug,release}/` — there is no native build
step in your project.

| | |
|---|---|
| **Requires** | Godot 4.6.x or newer · Board OS 1.3.8 or newer |
| **Docs** | https://docs.dev.board.fun/ |
| **FAQ (read first)** | https://docs.dev.board.fun/faq |
| **Developer Portal** | https://dev.board.fun/ |
| **Discord** | https://discord.gg/KccHAYgykD |
| **Changelog** | https://docs.dev.board.fun/more/changelog |
| **License** | [LICENSE.md](LICENSE.md) — Board Developer Terms of Use |
| **Third-party notices** | [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) |
| **Contact** | hello@board.fun |

## Install

1. Copy `addons/board_sdk/` into your project's `res://addons/`.
2. Enable **Board SDK** in `Project → Project Settings → Plugins`.
3. Add the `Board` autoload: `Project → Project Settings → Globals → Autoload`,
   path `res://addons/board_sdk/board.gd`, name `Board`.

Then guard every SDK call with `if not Board.is_on_device: return` and call
`Board.initialize("<your-app-id>")` once at startup. See the full setup, build,
and deploy guide in the SDK README and at https://docs.dev.board.fun/.
