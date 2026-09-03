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
    static var size: Int { d.object(forKey: "size") as? Int ?? 1 }        // 0 small · 1 medium · 2 large
    // Theme knobs. Presets just set these; each stays editable.
    static var radius: Double { d.object(forKey: "th.radius") as? Double ?? 18 }
    static var detached: Bool { d.bool(forKey: "th.detached") }
    static var textStyle: Int { d.integer(forKey: "th.text") }             // 0 rounded · 1 mono · 2 default
    static var glass: Bool { d.bool(forKey: "th.glass") }
    static var border: Bool { d.bool(forKey: "th.border") }
    static var showBars: Bool { d.object(forKey: "th.bars") as? Bool ?? true }
    static var thickBars: Bool { d.bool(forKey: "th.thickBars") }
    static var uppercase: Bool { d.bool(forKey: "th.upper") }
    static var titleDesign: Font.Design { [.rounded, .monospaced, .default][textStyle] }

    struct Preset { let name: String; let radius: Double; let detached: Bool; let text: Int; let glass: Bool; let border: Bool; let thickBars: Bool; let upper: Bool; let worker: Bool }
    static let presets: [Preset] = [
        Preset(name: "Notch", radius: 18, detached: false, text: 0, glass: false, border: false, thickBars: false, upper: false, worker: true),
        Preset(name: "Pill",  radius: 99, detached: true,  text: 0, glass: false, border: false, thickBars: false, upper: false, worker: true),
        Preset(name: "Pixel", radius: 4,  detached: false, text: 1, glass: false, border: false, thickBars: true,  upper: true,  worker: true),
        Preset(name: "Glass", radius: 22, detached: false, text: 2, glass: true,  border: true,  thickBars: false, upper: false, worker: true),
        Preset(name: "Mono",  radius: 12, detached: false, text: 1, glass: false, border: false, thickBars: false, upper: false, worker: false),
    ]
    static func apply(_ p: Preset) {
        d.set(p.radius, forKey: "th.radius"); d.set(p.detached, forKey: "th.detached"); d.set(p.text, forKey: "th.text")
        d.set(p.glass, forKey: "th.glass"); d.set(p.border, forKey: "th.border"); d.set(p.thickBars, forKey: "th.thickBars")
        d.set(p.upper, forKey: "th.upper"); d.set(p.worker, forKey: "showWorker")
    }
    /// Which preset matches the current knobs, if any.
    static var currentPreset: String? {
        presets.first { $0.radius == radius && $0.detached == detached && $0.text == textStyle && $0.glass == glass && $0.border == border && $0.thickBars == thickBars && $0.upper == uppercase && $0.worker == showWorker }?.name
    }
    static var accentMode: Int { d.integer(forKey: "accentMode") }           // 0 terracotta · 1 album art · 2 custom
    static var accentHex: String { d.string(forKey: "accentHex") ?? "D97757" }
    static func source(_ k: String) -> Bool { d.object(forKey: "src.\(k)") as? Bool ?? true }
    /// Tab order. Built-ins: music · claude · calendar. Agents: "agent:<name>".
    static var tabs: [String] {
        get { (d.string(forKey: "tabs")).flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? ["music", "claude", "calendar"] }
        set { d.set(String(data: try! JSONEncoder().encode(newValue), encoding: .utf8), forKey: "tabs"); NotificationCenter.default.post(name: .tabsChanged, object: nil) }
    }
    static let knownAgents = ["Codex", "Gemini", "Cursor", "Antigravity", "Copilot", "Kiro", "Windsurf"]
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
    @AppStorage("size") private var size = 1
    @AppStorage("th.radius") private var radius = 18.0
    @AppStorage("th.detached") private var detached = false
    @AppStorage("th.text") private var textStyle = 0
    @AppStorage("th.glass") private var glass = false
    @AppStorage("th.border") private var border = false
    @AppStorage("th.bars") private var showBars = true
    @AppStorage("th.thickBars") private var thickBars = false
    @AppStorage("th.upper") private var uppercase = false
    @State private var preset: String? = Prefs.currentPreset
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
                PillPreview().frame(maxWidth: .infinity).frame(height: 96).listRowInsets(EdgeInsets())
                HStack(spacing: 8) {
                    ForEach(Prefs.presets, id: \.name) { p in
                        Button(p.name) { Prefs.apply(p); reloadTheme() }
                            .buttonStyle(.bordered)
                            .tint(preset == p.name ? .accentColor : .secondary)
                    }
                }
                Picker("Shape", selection: $detached) { Text("Part of the notch").tag(false); Text("Floating pill").tag(true) }
                LabeledContent("Corner radius") {
                    HStack { Slider(value: $radius, in: 4...40, step: 1).frame(width: 160); Text("\(Int(radius))").monospacedDigit().frame(width: 30, alignment: .trailing) }
                }
                Picker("Text", selection: $textStyle) { Text("Rounded").tag(0); Text("Mono").tag(1); Text("System").tag(2) }
                Toggle("Uppercase labels", isOn: $uppercase)
                Picker("Material", selection: $glass) { Text("Black").tag(false); Text("Glass").tag(true) }
                Toggle("Hairline border", isOn: $border)
                Toggle("Activity bars", isOn: $showBars)
                Toggle("Thick bars", isOn: $thickBars).disabled(!showBars)
                Picker("Claude colour", selection: $accentMode) {
                    Text("Terracotta").tag(0); Text("Follow album art").tag(1); Text("Custom").tag(2)
                }
                if accentMode == 2 {
                    ColorPicker("Custom colour", selection: Binding(get: { Color(hex: accentHex) }, set: { accentHex = $0.hex }), supportsOpacity: false)
                }
                Toggle("Reduce animation", isOn: $reduceAnimation)
                Toggle("Show the pixel worker", isOn: $showWorker)
                Picker("Island size", selection: $size) { Text("Small").tag(0); Text("Medium").tag(1); Text("Large").tag(2) }.pickerStyle(.segmented)
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
            Section("Tabs") {
                TabsEditor()
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
        .onChange(of: [radius, Double(textStyle)] + [detached, glass, border, thickBars, uppercase, showWorker].map { $0 ? 1 : 0 }) { _, _ in preset = Prefs.currentPreset }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibility = AXIsProcessTrusted(); hooksInstalled = SettingsView.hooksPresent()
        }
    }

    /// After a preset writes UserDefaults directly, pull the values back into the bound @AppStorage properties.
    private func reloadTheme() {
        radius = Prefs.radius; detached = Prefs.detached; textStyle = Prefs.textStyle; glass = Prefs.glass
        border = Prefs.border; thickBars = Prefs.thickBars; uppercase = Prefs.uppercase; showWorker = Prefs.showWorker
        preset = Prefs.currentPreset
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


extension Notification.Name { static let tabsChanged = Notification.Name("tabsChanged") }

/// Drag to reorder; swipe or − to remove agent tabs; + to add one. The three built-ins can be reordered but not removed.
struct TabsEditor: View {
    @State private var tabs = Prefs.tabs
    @State private var custom = ""

    var body: some View {
        // ponytail: List.onMove is flaky inside a grouped Form on macOS, so rows carry ▲▼ and also accept drag.
        ForEach(Array(tabs.enumerated()), id: \.element) { i, t in
            HStack(spacing: 8) {
                Text(TabsEditor.title(t)).frame(maxWidth: .infinity, alignment: .leading)
                Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == tabs.count - 1)
                Button { tabs.removeAll { $0 == t }; Prefs.tabs = tabs } label: { Image(systemName: "minus.circle") }
                    .disabled(!t.hasPrefix("agent:")).opacity(t.hasPrefix("agent:") ? 1 : 0.3)
            }
            .buttonStyle(.borderless)
            .draggable(t)
            .dropDestination(for: String.self) { items, _ in
                guard let from = items.first, let a = tabs.firstIndex(of: from), let b = tabs.firstIndex(of: t), a != b else { return false }
                tabs.move(fromOffsets: IndexSet(integer: a), toOffset: b > a ? b + 1 : b); Prefs.tabs = tabs; return true
            }
        }
        HStack {
            Menu("Add an agent") {
                ForEach(Prefs.knownAgents.filter { !tabs.contains("agent:" + $0.lowercased()) }, id: \.self) { a in
                    Button(a) { tabs.append("agent:" + a.lowercased()); Prefs.tabs = tabs }
                }
            }.fixedSize()
            TextField("or type a name", text: $custom).textFieldStyle(.roundedBorder).frame(width: 140)
                .onSubmit { let n = custom.trimmingCharacters(in: .whitespaces).lowercased(); guard !n.isEmpty else { return }; tabs.append("agent:" + n); Prefs.tabs = tabs; custom = "" }
        }
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d; guard tabs.indices.contains(j) else { return }
        tabs.swapAt(i, j); Prefs.tabs = tabs
    }

    static func title(_ t: String) -> String {
        switch t { case "music": "Music"; case "claude": "Claude"; case "calendar": "Calendar"; default: String(t.dropFirst(6)).capitalized }
    }
}


/// A compact pill drawn with the current theme, on a mock menu bar, so changes read instantly.
struct PillPreview: View {
    @AppStorage("th.radius") private var radius = 18.0
    @AppStorage("th.detached") private var detached = false
    @AppStorage("th.text") private var textStyle = 0
    @AppStorage("th.glass") private var glass = false
    @AppStorage("th.border") private var border = false
    @AppStorage("th.bars") private var showBars = true
    @AppStorage("th.thickBars") private var thickBars = false
    @AppStorage("th.upper") private var uppercase = false
    @AppStorage("showWorker") private var showWorker = true
    @AppStorage("size") private var size = 1

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.24, green: 0.47, blue: 0.72), Color(red: 0.18, green: 0.36, blue: 0.58)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(white: 0.12)).padding(.top, 32)
            HStack { Text("Finder  File  Edit").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white); Spacer(); Text("Thu 3 Sep  15.35").font(.system(size: 12)).foregroundStyle(.white) }
                .padding(.horizontal, 14).frame(height: 32)
            Rectangle().fill(.black).frame(width: 120, height: 32).clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            IslandSurface(radius: radius, detached: detached, glass: glass, border: border, compact: true)
                .frame(width: 120 + 2 * [90, 105, 120][size], height: 32)
                .overlay {
                    HStack(spacing: 0) {
                        HStack(spacing: 6) { Record(image: nil, playing: false, size: 16); label("Ivy") ; Spacer(minLength: 0) }.padding(.horizontal, 10).frame(width: [90, 105, 120][size])
                        Group { if showBars { Bars(levels: [0.4, 0.9, 0.3, 0.7, 0.5], color: Palette.claude, thick: thickBars) } else { Color.clear } }.frame(width: 120)
                        HStack(spacing: 6) { Spacer(minLength: 0); label("Editing app.ts", mono: true); if showWorker { Sprite(phase: .working(tool: "Edit", target: ""), size: 16) } else { Orb(phase: .working(tool: "Edit", target: ""), size: 9) } }.padding(.horizontal, 10).frame(width: [90, 105, 120][size])
                    }
                    .foregroundStyle(.white)
                    .offset(y: detached ? 6 : 0)
                }
                .offset(y: detached ? 6 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func label(_ t: String, mono: Bool = false) -> some View {
        Text(uppercase ? t.uppercased() : t)
            .font(.system(size: mono ? 10 : 11, weight: .semibold, design: mono ? .monospaced : [.rounded, .monospaced, .default][textStyle]))
            .lineLimit(1)
    }
}
