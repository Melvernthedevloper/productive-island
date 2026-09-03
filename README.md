# Productive Island

A Dynamic Island for the MacBook notch that shows what Claude is doing — Claude Code in your terminal, Cowork tasks and chats in the Claude app — next to what you're listening to and what's next on your calendar.

- **Claude Code** — which tool is running, on which file, for how long. Finished → chime and a peek at the reply. Needs permission → the island asks, you answer with ⏎ / ⎋ without leaving your editor.
- **Cowork & chat** — same states for the Claude desktop app.
- **Spotify** — track, artwork as a spinning record, transport controls.
- **Calendar** — next event with a Join button; Today / Tomorrow / Week.
- **Plan usage** — session and weekly limits with reset times, one click away.

Native SwiftUI, ~30 MB, no accounts, no network calls except Spotify artwork. Everything is read from what the apps already write to your disk.

## Requirements

- macOS 14 or newer, a Mac with a notch (works on other displays with a fake notch)
- Xcode command line tools (`xcode-select --install`)
- Claude Code, and optionally the Claude desktop app and Spotify

## Install

```sh
git clone https://github.com/<you>/productive-island.git
cd productive-island
./make-app.sh            # builds ProductiveIsland.app
open ProductiveIsland.app
```

Then tell Claude Code to talk to it (once):

```sh
.build/release/ProductiveIsland --install-hooks
```

This appends hook entries to `~/.claude/settings.json`. It never removes anything that isn't its own. Hooks take effect in Claude Code sessions started afterwards.

### Permissions macOS will ask for

| Prompt | Why | Needed for |
|---|---|---|
| Calendars | read today's events | Calendar tab |
| Automation → Spotify | play / pause / skip | transport buttons (reading the track needs nothing) |
| Accessibility | see the Claude app's "Stop response" button | chat in the Claude app |

Decline any of them and that one feature stays off; the rest keeps working. Accessibility is read-only — the app looks for one button label in the Claude window and never sends input.

### Optional

- **Plan usage without the Claude app**: add this line to your Claude Code status line script so the island gets `rate_limits` on every reply:
  ```sh
  printf '%s' "$input" | nc -U "$HOME/Library/Application Support/ProductiveIsland/sock" -w 1 2>/dev/null || :
  ```
- **Custom sounds**: drop `done.aiff` / `attention.aiff` into `~/Library/Application Support/ProductiveIsland/`.
- **Launch at login**: System Settings → General → Login Items → add `ProductiveIsland.app`.

## Using it

| Do | Get |
|---|---|
| glance at the notch | left: music · middle: pulse bars · right: Claude's status + the pixel worker |
| hover | the panel opens on the last tab |
| two-finger swipe / click the strip | Music · Claude · Calendar |
| click the footer `session · model ›` | plan limits |
| ⏎ / ⎋ while the amber card is up | allow / deny a Claude Code permission |
| `↗` on any row | jump to that session's app |
| speaker icon | mute the chimes |

## How it works

| Source | Mechanism |
|---|---|
| Claude Code | official hooks → Unix socket (`nc -U`), including the blocking `PermissionRequest` hook for Allow/Deny |
| Cowork | tails the session's `audit.jsonl` the Claude app writes |
| Claude chat | Accessibility: the "Stop response" button exists only while a reply streams |
| Plan usage | `plan-usage-history.json` written by the Claude app, plus `rate_limits` from the status line |
| Spotify | `com.spotify.client.PlaybackStateChanged` distributed notification; artwork via the public oEmbed endpoint |
| Calendar | EventKit |

Five Swift files plus the sprite. Start with `PLAN.md` for the design.

## Develop

```sh
swift build                      # debug build
.build/debug/ProductiveIsland --sprites sheet.png   # render the pixel worker's frames
.build/debug/ProductiveIsland --icon icon.png       # render the app icon
```

Fake an event without Claude:

```sh
echo '{"hook_event_name":"PreToolUse","session_id":"t","tool_name":"Edit","cwd":"'$PWD'","tool_input":{"file_path":"x.swift"}}' \
  | nc -U "$HOME/Library/Application Support/ProductiveIsland/sock" -w 1
```

## License

MIT
