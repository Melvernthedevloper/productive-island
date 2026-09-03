# Productive Island — plan

A Dynamic Island for the Mac notch. Left lobe = what you're listening to. Right lobe = what Claude Code is doing. It should read like a piece of the hardware, not an app.

## Decisions (assumed — say so if wrong)

| Axis | Choice | Why |
|---|---|---|
| Stack | Native SwiftUI + AppKit `NSPanel` | Only way to sit *inside* the notch geometry with 120 Hz spring morphs at ~30 MB RAM. Electron/Tauri fight the notch. |
| Claude Code feed | Official hooks → Unix socket | `PreToolUse / PostToolUse / Notification / Stop` already emit JSON on stdin. `curl --unix-socket … -d @-` ships it. No polling, no parsing internal formats. |
| Claude response text | `Stop` hook's `transcript_path` → read last assistant message | One file read per response, not a tail loop. |
| Spotify feed | `DistributedNotificationCenter` `com.spotify.client.PlaybackStateChanged` + AppleScript for artwork/controls | Local, no OAuth, push not poll. Fallback to Web API is v2 only if you want phone playback. |
| Distribution | Unsigned `.app` you build yourself, launch-at-login | It's for you. Notarization is a later problem. |

## Design

### Subject
The notch is a hole in the hardware. The island is the thing that grows out of it. Every choice should feel like Apple made it and Anthropic/Spotify rent space in it — black, rounded, physical. Vernacular: VU meters, tape counters, the cadence of a terminal streaming tokens.

### Tokens
```
color.notch      #000000   the island body — must match the real notch exactly
color.ink        #0A0A0A   expanded panel surface
color.text       #F2F2F2
color.dim        #8E8E93   metadata, timers
color.claude     #D97757   Claude's own terracotta — used ONLY for "thinking"
color.attention  #FFB340   permission prompt, pulses
color.ok         #30D158   Stop / done, holds 2s then fades
color.spotify    extracted from artwork; fallback #1DB954
```
Only one accent is ever lit at a time. Terracotta is a default-AI-palette colour elsewhere; here it's justified because it is literally the subject's brand.

```
type.compact   SF Pro Rounded  13/600   labels in the pill (matches Apple's island)
type.body      SF Pro          13/400   response peek text
type.mono      SF Mono         11/500   file paths, tool names, timers — tabular figures
```
No custom fonts. A HUD that lives in the bezel must use the system's face or it reads as a sticker.

### Signature
**The bars are the state.** A 5-bar meter sits in the middle of the compact pill. When music plays, it's the audio level. When Claude is thinking, the same bars pulse *per streamed token chunk* in terracotta — you can literally see it typing. Idle: bars rest at 1 px. One element carries both subjects; nothing else in the pill animates.

### States & layout

```
                       ┌──── real notch ────┐
compact  ( ♪ Ivy  ▮▮▯▮▯ │████████████████████│ ▮▮▮▯▯  Edit · island.swift  0:42 )
                       └────────────────────┘
          left lobe: Spotify         bars        right lobe: Claude Code

expanded (hover or event, ~2.5s)
         ┌───────────────────────────────────────────────────────────────┐
         │ [art]  Ivy                        ⣾ Edit                       │
         │        Frank Ocean · Blonde        ~/Island/island.swift        │
         │        ◁  ⏸  ▷    ─────●───── 2:14  session: vibe-island  0:42 │
         └───────────────────────────────────────────────────────────────┘

response peek (on Stop)
         ┌───────────────────────────────────────────────────────────────┐
         │ ● Done · 0:58                                          ⌄  ↗   │
         │ Added the socket listener and wired PreToolUse. Two tests pass │
         │ — `swift test` is green. Want me to add the Spotify observer?  │
         └───────────────────────────────────────────────────────────────┘
          ⌄ expand full text     ↗ focus the terminal that sent it

permission (on Notification: permission_prompt)
         (  ⚠ Allow  rm -rf build/ ?             ✓ Allow    ✕ Deny  )
          whole pill pulses attention colour at 1 Hz until answered
```

Expanded panel morphs from the pill with `matchedGeometryEffect`; the corners stay continuous with the notch's own radius so it looks like the bezel is stretching. Spring: `response 0.45, dampingFraction 0.78`. Reduced motion → crossfade, bars freeze.

Empty states are instructions, not moods: no Spotify → left lobe collapses. No Claude session → "Run `vibe hooks install`" once, then collapses.

## Architecture (5 files)

```
ProductiveIsland/
  ProductiveIslandApp.swift    NSPanel: .statusBar level, non-activating, transparent,
                         frame = NSScreen.main.auxiliaryTopLeftArea ∪ topRightArea
  IslandView.swift       compact / expanded / peek / permission + morph
  Bars.swift             the meter; takes a [Float] level source
  ClaudeFeed.swift       NWListener on ~/Library/Application Support/ProductiveIsland/sock
                         decodes hook JSON → @Observable ClaudeState
                         on Stop: read transcript_path, take last assistant text
  SpotifyFeed.swift      DistributedNotificationCenter observer → @Observable TrackState
                         AppleScript for artwork, play/pause/next, seek
```

Hook install = one command that appends to `~/.claude/settings.json`:
```json
"hooks": {
  "PreToolUse":   [{"hooks":[{"type":"command","command":"curl -s --unix-socket $VIBE_SOCK -d @- http://vibe/event"}]}],
  "PostToolUse":  [ same ],
  "Notification": [ same ],
  "Stop":         [ same ]
}
```
Hooks must exit fast → `curl -m 0.2`. If the app isn't running, curl fails silently and Claude Code is unaffected.

Permission approve/deny inline: hooks can't answer prompts for you, so ✓/✕ send the keystroke to the originating terminal via Accessibility (needs one permission grant). If you'd rather not grant AX, the buttons just focus the terminal.

## Phases

1. **Shell** — panel under the notch, compact pill, bars idle. Screenshot it, tune radius until it's invisible against the bezel.
2. **Claude** — socket + hooks install + tool/file/timer in right lobe + terracotta bars on PreToolUse.
3. **Spotify** — notification observer, artwork colour, transport controls in expanded.
4. **Peek + permission** — Stop → response peek; Notification → attention state.

Each phase leaves one runnable check: phase 2 = `echo '{"hook_event_name":"PreToolUse","tool_name":"Edit"}' | curl --unix-socket … -d @-` lights the island.

## Skipped, and when to add
- Web API / phone playback → when you listen on something other than this Mac.
- Multiple concurrent Claude sessions → when you actually run two; v1 shows the most recent event's session.
- Token/cost counters → after v1, from the same transcript file.
