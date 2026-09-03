import AppKit
import SwiftUI

if let i = CommandLine.arguments.firstIndex(of: "--sprites"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { SpriteSheet.render(to: CommandLine.arguments[i + 1]) }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { SpriteSheet.renderIcon(to: CommandLine.arguments[i + 1]) }
    exit(0)
}
if CommandLine.arguments.contains("--install-hooks") {
    try ClaudeFeed.installHooks()
    exit(0)
}

/// System chime, overridable by dropping `<name>.aiff` into ~/Library/Application Support/ProductiveIsland/.
enum Sound {
    static func play(_ name: String, fallback: String) {
        guard UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true else { return }
        let custom = (ClaudeFeed.socketPath as NSString).deletingLastPathComponent + "/\(name).aiff"
        let s = NSSound(contentsOfFile: custom, byReference: true) ?? NSSound(named: fallback)
        s?.volume = 0.6
        s?.play()
    }
}

/// Notch geometry for the main screen. Falls back to a fake notch on external displays.
struct Notch {
    let width: CGFloat
    let height: CGFloat
    let centerX: CGFloat   // in screen coords
    let screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
        let f = screen.frame
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            width = r.minX - l.maxX
            height = screen.safeAreaInsets.top
            centerX = l.maxX + width / 2
        } else {
            width = 180; height = 32; centerX = f.midX  // ponytail: fake notch on external displays
        }
    }
}

final class IslandPanel: NSPanel {
    init(notch: Notch, claude: ClaudeState, spotify: SpotifyFeed, calendar: CalendarFeed, chat: ClaudeAppFeed) {
        let size = IslandMetrics.panelSize(notch: notch)
        let origin = NSPoint(x: notch.centerX - size.width / 2,
                             y: notch.screen.frame.maxY - size.height)
        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        contentView = NSHostingView(rootView: IslandView(notch: notch, claude: claude, spotify: spotify, calendar: calendar, chat: chat))
    }
    override var canBecomeKey: Bool { true }   // key only while a permission card is up (for ⏎ / ⎋)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: IslandPanel?
    var feed: ClaudeFeed?
    var desktop: ClaudeDesktopFeed?
    var chat: ClaudeAppFeed?
    let claude = ClaudeState()
    let spotify = SpotifyFeed()
    let calendar = CalendarFeed()

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let screen = NSScreen.main else { return }
        let chat = ClaudeAppFeed(state: claude)
        self.chat = chat
        let p = IslandPanel(notch: Notch(screen: screen), claude: claude, spotify: spotify, calendar: calendar, chat: chat)
        p.orderFrontRegardless()
        panel = p
        let claude = self.claude
        feed = try? ClaudeFeed { e, conn in
            Task { @MainActor in claude.apply(e, decide: { ClaudeFeed.answer(conn, allow: $0) }) }
        }
        desktop = ClaudeDesktopFeed(state: claude)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
