import AppKit
import EventKit
import ServiceManagement
import SwiftUI

/// Every user-facing knob. Stored in UserDefaults; read where needed via @AppStorage or `Prefs.*`.
enum Prefs {
    static let d = UserDefaults.standard
    static var soundOn: Bool { d.object(forKey: "soundOn") as? Bool ?? true }
    static var linger: Double { d.object(forKey: "linger") as? Double ?? 2 }
    static var hoverDelay: Double { d.object(forKey: "hoverDelay") as? Double ?? 0.15 }
    static var reduceAnimation: Bool { d.bool(forKey: "reduceAnimation") }
    static var showWorker: Bool { d.object(forKey: "showWorker") as? Bool ?? true }
    static var compactLobe: Bool { d.bool(forKey: "compactLobe") }
    static var accentMode: Int { d.integer(forKey: "accentMode") }           // 0 terracotta · 1 album art · 2 custom
    static var accentHex: String { d.string(forKey: "accentHex") ?? "D97757" }
    static func source(_ k: String) -> Bool { d.object(forKey: "src.\(k)") as? Bool ?? true }
    static var hasSeenTutorial: Bool { get { d.bool(forKey: "hasSeenTutorial") } set { d.set(newValue, forKey: "hasSeenTutorial") } }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0; Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// The Settings window: made on demand, released on close, so it costs nothing while shut.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    var onReplayTutorial: (() -> Void)?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Productive Island Settings"
            w.contentView = NSHostingView(rootView: SettingsView(replayTutorial: { [weak self] in self?.window?.close(); self?.onReplayTutorial?() }))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ n: Notification) { window = nil }
}

struct SettingsView: View {
    var replayTutorial: () -> Void
    @AppStorage("soundOn") private var soundOn = true
    @AppStorage("linger") private var linger = 2.0
    @AppStorage("hoverDelay") private var hoverDelay = 0.15
    @AppStorage("reduceAnimation") private var reduceAnimation = false
    @AppStorage("showWorker") private var showWorker = true
    @AppStorage("compactLobe") private var compactLobe = false
    @AppStorage("accentMode") private var accentMode = 0
    @AppStorage("accentHex") private var accentHex = "D97757"
    @AppStorage("calendarScope") private var scope: Scope = .today
    @AppStorage("src.code") private var srcCode = true
    @AppStorage("src.cowork") private var srcCowork = true
    @AppStorage("src.chat") private var srcChat = true
    @AppStorage("src.spotify") private var srcSpotify = true
    @AppStorage("src.calendar") private var srcCalendar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hooksInstalled = SettingsView.hooksPresent()
    @State private var accessibility = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Toggle("Sounds", isOn: $soundOn)
                LabeledContent("Close after the cursor leaves") {
                    HStack { Slider(value: $linger, in: 0...5, step: 0.5).frame(width: 160); Text(String(format: "%.1f s", linger)).monospacedDigit().frame(width: 40, alignment: .trailing) }
                }
                LabeledContent("Open after hovering") {
                    HStack { Slider(value: $hoverDelay, in: 0...1, step: 0.05).frame(width: 160); Text(String(format: "%.2f s", hoverDelay)).monospacedDigit().frame(width: 40, alignment: .trailing) }
                }
            }
            Section("Appearance") {
                Picker("Claude colour", selection: $accentMode) {
                    Text("Terracotta").tag(0); Text("Follow album art").tag(1); Text("Custom").tag(2)
                }
                if accentMode == 2 {
                    ColorPicker("Custom colour", selection: Binding(get: { Color(hex: accentHex) }, set: { accentHex = $0.hex }), supportsOpacity: false)
                }
                Toggle("Reduce animation", isOn: $reduceAnimation)
                Toggle("Show the pixel worker", isOn: $showWorker)
                Toggle("Compact island (13-inch)", isOn: $compactLobe)
            }
            Section("Sources") {
                sourceRow("Claude Code", $srcCode, ok: hooksInstalled, fix: "Install hooks") { try? ClaudeFeed.installHooks(); hooksInstalled = SettingsView.hooksPresent() }
                sourceRow("Cowork (Claude app)", $srcCowork, ok: true, fix: nil) {}
                sourceRow("Chat (Claude app)", $srcChat, ok: accessibility, fix: "Allow Accessibility") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                sourceRow("Spotify", $srcSpotify, ok: true, fix: nil) {}
                sourceRow("Calendar", $srcCalendar, ok: EKEventStore.authorizationStatus(for: .event) == .fullAccess, fix: "Allow Calendar") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                Picker("Calendar shows", selection: $scope) { ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            Section {
                Button("Replay the tutorial", action: replayTutorial)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                Link("Source on GitHub", destination: URL(string: "https://github.com/Melvernthedevloper/productive-island")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibility = AXIsProcessTrusted(); hooksInstalled = SettingsView.hooksPresent()
        }
    }

    private func sourceRow(_ name: String, _ on: Binding<Bool>, ok: Bool, fix: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Toggle(name, isOn: on)
            Spacer()
            if on.wrappedValue {
                if ok { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else if let fix { Button(fix, action: action).controlSize(.small) }
            }
        }
    }

    static func hooksPresent() -> Bool {
        ((try? String(contentsOfFile: NSHomeDirectory() + "/.claude/settings.json", encoding: .utf8)) ?? "").replacingOccurrences(of: "\\/", with: "/").contains("ProductiveIsland/sock")
    }
}
