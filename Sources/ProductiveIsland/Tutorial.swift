import AppKit
import EventKit
import SwiftUI

/// First-run walkthrough, shown inside the island itself with example data. Six steps; the last is the setup checklist.
struct Tutorial: View {
    static let height: CGFloat = 176
    let step: Int
    let notchHeight: CGFloat
    var spotify: SpotifyFeed
    let next: (Int?) -> Void
    let finish: () -> Void
    static let count = 6
    @State private var levels: [CGFloat] = [0.4, 0.9, 0.3, 0.7, 0.5]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<Tutorial.count, id: \.self) { i in
                        Capsule().fill(i == step ? Color.white : Palette.rule).frame(width: i == step ? 14 : 5, height: 3)
                    }
                }
                Spacer()
                if step < Tutorial.count - 1 {
                    Button("Skip") { finish() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.dim)
                    Button { next(step + 1) } label: {
                        Text("Next").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 5).background(.white, in: Capsule())
                    }.buttonStyle(.plain)
                } else {
                    Button { finish() } label: {
                        Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 5).background(Palette.ok, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, notchHeight + 6).padding(.bottom, 10)
        .foregroundStyle(.white)
        .task(id: step) {
            // demo bars pulse on the first step; auto-advance every 6 s except on the checklist
            while !Task.isCancelled {
                levels = (0..<5).map { _ in CGFloat.random(in: 0.2...1) }
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
        .task(id: step) {
            guard step < Tutorial.count - 1 else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { next(step + 1) }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: step)
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 14, weight: .semibold, design: Prefs.titleDesign))
            Text(sub).font(.system(size: 11)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            title("This is your island", "It lives in the notch and shows three things at a glance.")
            HStack(spacing: 22) {
                demo(Record(image: nil, playing: true, size: 18), "music")
                demo(Bars(levels: levels, color: Palette.claude).frame(width: 40), "activity")
                demo(Sprite(phase: .working(tool: "Edit", target: ""), size: 18), "Claude")
            }.padding(.top, 4)
        case 1:
            title("Hover to open", "Three tabs underneath. Click a glyph, or swipe left and right with two fingers.")
            HStack(spacing: 22) {
                demo(SpotifyGlyph(size: 14), "Music")
                demo(Sprite(phase: nil, size: 14), "Claude")
                demo(Image(systemName: "calendar").font(.system(size: 12, weight: .bold)), "Calendar")
            }.padding(.top, 4)
        case 2:
            title("Claude at work", "Every Claude Code, Cowork or chat session gets a row. It chimes when a reply lands; ↗ jumps to that app.")
            HStack(spacing: 10) {
                Sprite(phase: .working(tool: "Edit", target: ""), size: 14)
                (Text("island").font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign)) + Text("  Editing IslandView.swift").font(.system(size: 11)).foregroundColor(Palette.dim))
                Spacer(); Text("0:42").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.dim); Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
            }.padding(.top, 2)
            Text("Footer  ›  opens your plan usage.").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.dim)
        case 3:
            title("Answer permissions here", "When Claude Code needs approval the island turns amber. ⏎ allows, ⎋ denies — no need to find the terminal.")
            HStack(spacing: 8) {
                Text("rm -rf .build/").font(.system(size: 11, weight: .medium, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 4).background(Palette.well, in: RoundedRectangle(cornerRadius: 6))
                Spacer()
                Text("Deny ⎋").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4).background(Color(white: 0.17), in: Capsule())
                Text("Allow ⏎").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 4).background(Palette.attention, in: Capsule())
            }.padding(.top, 2)
        case 4:
            title("Music and calendar", "Spotify controls and artwork; your next event with a Join button. Ten minutes before a meeting the island tells you.")
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.attention)
                Text("Standup").font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign))
                Text("4m").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.attention)
                Spacer()
                Text("Settings: ⚙ in the tab strip or right-click the island.").font(.system(size: 10)).foregroundStyle(Palette.dim)
            }.padding(.top, 2)
        default:
            title("Set up the sources", "Each one is optional. Green means ready.")
            Checklist()
        }
    }

    private func demo<V: View>(_ v: V, _ label: String) -> some View {
        VStack(spacing: 4) { v.frame(height: 20); Text(label).font(.system(size: 10)).foregroundStyle(Palette.dim) }
    }
}

/// Live permission checklist — the useful part of the tutorial, also reachable from Settings.
struct Checklist: View {
    @State private var hooks = SettingsView.hooksPresent()
    @State private var ax = AXIsProcessTrusted()
    @State private var cal = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    var body: some View {
        HStack(spacing: 14) {
            item("Claude Code hooks", hooks, "Install") { try? ClaudeFeed.installHooks(); hooks = SettingsView.hooksPresent() }
            item("Calendar", cal, "Allow") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
            item("Chat (Accessibility)", ax, "Allow") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
        }
        .padding(.top, 2)
        .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); ax = AXIsProcessTrusted(); cal = EKEventStore.authorizationStatus(for: .event) == .fullAccess } }
    }

    private func item(_ name: String, _ ok: Bool, _ fix: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Palette.ok : Palette.dim).font(.system(size: 11))
                Text(name).font(.system(size: 11, weight: .medium))
            }
            if !ok {
                Button(fix, action: action).buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.attention)
            } else {
                Text("ready").font(.system(size: 10)).foregroundStyle(Palette.dim)
            }
        }
    }
}
