import AppKit
import EventKit
import SwiftUI

enum IslandMetrics {
    // Small / Medium / Large: lobe width and panel heights scale; type stays readable at every size.
    static var scale: CGFloat { [0.78, 1.0, 1.15][Prefs.size] }
    static var lobe: CGFloat { [125, 175, 205][Prefs.size] }
    static var panelHeight: CGFloat { 108 * scale }      // grows down only — width stays the compact width
    static var settingsHeight: CGFloat { 150 * scale }
    static let rowHeight: CGFloat = 22
    static let usageHeight: CGFloat = 16
    static let usageDetailHeight: CGFloat = 36
    static var weekHeight: CGFloat { 150 * scale }
    static var cardHeight: CGFloat { 170 * scale }
    static var fullHeight: CGFloat { 260 * scale }
    static var corner: CGFloat { Prefs.radius }
    static var drop: CGFloat { Prefs.detached ? 6 : 0 }     // floating pill sits a little below the bezel
    static var hoverDelay: Duration { .milliseconds(Int(Prefs.hoverDelay * 1000)) }
    static var linger: TimeInterval { Prefs.linger }          // stays open this long after the cursor leaves

    /// The NSPanel is sized once, for the largest setting; the island centres inside it.
    static func panelSize(notch: Notch) -> CGSize {
        CGSize(width: notch.width + 2 * 205 + 40, height: 260 * 1.15 + 40)
    }
}

enum Palette {
    static let terracotta = Color(red: 0xD9/255, green: 0x77/255, blue: 0x57/255)
    static var claude: Color { Prefs.accentMode == 2 ? Color(hex: Prefs.accentHex) : terracotta }
    static let attention = Color(red: 1.0, green: 0xB3/255, blue: 0x40/255)
    static let ok = Color(red: 0x30/255, green: 0xD1/255, blue: 0x58/255)
    static let dim = Color(white: 0.56)
    static let rule = Color(white: 0.18)
    static let well = Color(white: 0.08)
}

enum Tab { static let music = "music", claude = "claude", calendar = "calendar" }
enum Scope: String, CaseIterable { case today = "Today", tomorrow = "Tomorrow", week = "Week" }

struct IslandView: View {
    let notch: Notch
    var claude: ClaudeState
    var spotify: SpotifyFeed
    var calendar: CalendarFeed
    var chat: ClaudeAppFeed

    @State private var hovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var pinned = false
    @State private var showFull: String?         // session id whose full response is open
    @State private var tab: String = Tab.claude
    @State private var tabs: [String] = Prefs.tabs
    @State private var showAddAgent = false
    @State private var levels: [CGFloat] = [0, 0, 0, 0, 0]
    @State private var swipeX: CGFloat = 0
    @State private var chimed: Set<String> = []  // session ids already chimed for this done
    @State private var keyMonitor: Any?
    @State private var showUsage = false
    @State private var tutorial: Int? = nil        // current tutorial step, nil = not running
    @AppStorage("soundOn") private var soundOn = true
    @AppStorage("calendarScope") private var scope: Scope = .today
    @AppStorage("showWorker") private var showWorker = true
    @AppStorage("size") private var size = 1
    @AppStorage("linger") private var lingerPref = 2.0
    @AppStorage("reduceAnimation") private var reduceAnimation = false
    @State private var showSettings = false
    @AppStorage("accentMode") private var accentMode = 0
    @AppStorage("accentHex") private var accentHex = "D97757"
    @AppStorage("src.spotify") private var srcSpotify = true
    @AppStorage("src.calendar") private var srcCalendar = true

    private var card: ClaudeState.Session? { claude.waiting }
    private var expanded: Bool { hovering || pinned || showFull != nil || card != nil || tutorial != nil || showSettings }
    private var width: CGFloat { notch.width + 2 * IslandMetrics.lobe }
    private var height: CGFloat {
        if !expanded { return notch.height }
        if tutorial != nil { return Tutorial.height }
        if showSettings { return IslandMetrics.settingsHeight }
        if card != nil { return IslandMetrics.cardHeight }
        if showFull != nil { return IslandMetrics.fullHeight }
        switch tab {
        case Tab.claude: return IslandMetrics.panelHeight + IslandMetrics.usageHeight + (showUsage ? IslandMetrics.usageDetailHeight : 0)
            + IslandMetrics.rowHeight * CGFloat(max(0, min(claudeSessions.count, 5) - 3))
        case Tab.calendar: return scope == .week ? IslandMetrics.weekHeight : IslandMetrics.panelHeight
        case Tab.music: return IslandMetrics.panelHeight
        default: return IslandMetrics.panelHeight + IslandMetrics.rowHeight * CGFloat(max(0, min(agentSessions(tab).count, 5) - 3))
        }
    }

    /// Claude's own sessions (code, cowork, chat); agents get their own tabs.
    private var claudeSessions: [ClaudeState.Session] { claude.ordered.filter { if case .other = $0.source { false } else { true } } }
    private func agentSessions(_ t: String) -> [ClaudeState.Session] { claude.ordered.filter { $0.source == .other(String(t.dropFirst(6))) } }
    private func agentColor(_ t: String) -> Color {
        let hues: [Double] = [0.47, 0.58, 0.72, 0.85, 0.1, 0.3, 0.63]
        return Color(hue: hues[abs(t.hashValue) % hues.count], saturation: 0.55, brightness: 0.9)
    }

    private var accent: Color {
        if card != nil { return Palette.attention }
        if let p = claude.primary {
            if p.isDone && p.urgency == 1 { return Palette.ok }
            if claude.anyWorking { return Prefs.accentMode == 1 && spotify.state.hasTrack ? spotify.state.accent : Palette.claude }
        }
        return spotify.state.playing ? spotify.state.accent : .white.opacity(0.9)
    }
    /// Calendar borrows the left lobe when something starts within 10 minutes.
    private var soonEvent: EKEvent? {
        if srcCalendar, let m = calendar.minutesToNext(), m <= 10, m >= -1 { return calendar.next }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandSurface(radius: IslandMetrics.corner, detached: Prefs.detached, glass: Prefs.glass, border: Prefs.border, compact: !expanded)
                if card != nil {
                    IslandShape(radius: IslandMetrics.corner, detached: Prefs.detached).strokeBorder(Palette.attention.opacity(0.9), lineWidth: 1.5)
                }
                if expanded { panel } else { compact }
            }
            .frame(width: width, height: height)
            .offset(y: IslandMetrics.drop)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: height)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: size)
            .onHover(perform: hover)
            .contextMenu {
                Button("Settings…") { SettingsWindow.shared.show() }
                Button("Quit Productive Island") { NSApp.terminate(nil) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .task(id: claude.anyWorking || spotify.state.playing) {
            // ponytail: no token stream and no audio tap — both are random pulses at different tempos.
            guard claude.anyWorking || spotify.state.playing else { levels = [0, 0, 0, 0, 0]; return }
            while !Task.isCancelled {
                levels = (0..<5).map { _ in CGFloat.random(in: 0.15...1) }
                try? await Task.sleep(for: .milliseconds(claude.anyWorking ? 120 : 220))
            }
        }
        .task { while !Task.isCancelled { claude.prune(); try? await Task.sleep(for: .seconds(30)) } }
        .onChange(of: claude.sessions.map { "\($0.id):\($0.phase)" }) { _, _ in react() }
        .onChange(of: card?.id) { _, id in keyboard(active: id != nil) }
        .onChange(of: expanded) { _, open in if !open { showUsage = false; showSettings = false } }
        .onChange(of: tab) { _, _ in showUsage = false }
        .onChange(of: calendar.minutesToNext()) { _, m in if let m, m == 5 { open(Tab.calendar, for: .seconds(8)) } }
        .onChange(of: spotify.state.name) { _, _ in if expanded && card == nil { tab = Tab.music } }
        .onAppear {
            installSwipe()
            if ProcessInfo.processInfo.environment["PI_OPEN"] == "settings" { showSettings = true }   // for screenshots/tests
            if !Prefs.hasSeenTutorial { Task { try? await Task.sleep(for: .seconds(1)); tutorial = 0 } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .replayTutorial)) { _ in tutorial = 0 }
        .onReceive(NotificationCenter.default.publisher(for: .tabsChanged)) { _ in tabs = Prefs.tabs; if !tabs.contains(tab) { tab = tabs.first ?? Tab.claude } }
        // ponytail: SwiftUI's onHover misses the exit while the frame is animating, so poll the cursor while open.
        // The island lingers `linger` seconds after the cursor leaves; coming back inside cancels the close.
        .task(id: expanded) {
            guard expanded else { return }
            var leftAt: Date?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if mouseInside() { leftAt = nil; hovering = true; continue }
                if leftAt == nil { leftAt = Date() }
                if Date().timeIntervalSince(leftAt!) >= IslandMetrics.linger {
                    hoverTask?.cancel(); hovering = false; showSettings = false; showUsage = false; leftAt = nil
                }
            }
        }
    }

    /// Chime once per finished session; needs-you sound once per request; open the right tab.
    private func react() {
        for s in claude.sessions {
            let home: String = { if case .other(let n) = s.source { return "agent:" + n } else { return Tab.claude } }()
            if s.isDone, !chimed.contains(s.id) {
                chimed.insert(s.id); Sound.play("done", fallback: "Glass"); open(home, for: .seconds(6))
            } else if s.needsYou, !chimed.contains("perm:" + s.id) {
                chimed.insert("perm:" + s.id); Sound.play("attention", fallback: "Purr"); tab = home
            }
            if !s.isDone { chimed.remove(s.id) }
            if !s.needsYou { chimed.remove("perm:" + s.id) }
        }
        if let f = showFull, !claude.sessions.contains(where: { $0.id == f }) { showFull = nil }
    }

    private func mouseInside() -> Bool {
        let m = NSEvent.mouseLocation
        let f = notch.screen.frame
        return abs(m.x - notch.centerX) <= width / 2 + 8 && m.y >= f.maxY - height - 8
    }

    private func hover(_ on: Bool) {
        guard on else { return }                 // leaving is handled by the linger poll above
        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(for: IslandMetrics.hoverDelay)
            if !Task.isCancelled { hovering = true }
        }
    }

    private func open(_ t: String, for d: Duration) {
        tab = tabs.contains(t) ? t : (tabs.first ?? Tab.claude); pinned = true
        Task { try? await Task.sleep(for: d); if showFull == nil { pinned = false } }
    }

    /// ⏎ allows, ⎋ denies while a permission card is up. The panel takes key focus only then.
    private func keyboard(active: Bool) {
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        guard active else { NSApp.keyWindow?.resignKey(); return }
        NSApp.windows.first?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard let c = card else { if e.keyCode == 53, showUsage { showUsage = false; return nil }; return e }
            switch e.keyCode {
            case 36: claude.decide(c.id, allow: true); return nil
            case 53: claude.decide(c.id, allow: false); return nil
            default: return e
            }
        }
    }

    /// Two-finger horizontal swipe switches tabs.
    private func installSwipe() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard expanded, card == nil else { return e }
            if e.phase == .changed { swipeX += e.scrollingDeltaX }
            if e.phase == .ended {
                if let i = tabs.firstIndex(of: tab) {
                    if swipeX < -30, i + 1 < tabs.count { tab = tabs[i + 1] }
                    if swipeX > 30, i > 0 { tab = tabs[i - 1] }
                }
                swipeX = 0
            }
            return e
        }
    }

    // MARK: - compact pill

    private var compact: some View {
        HStack(spacing: 0) {
            leftLobe.frame(width: IslandMetrics.lobe)
            Group { if Prefs.showBars { Bars(levels: levels, color: accent) } else { Color.clear } }.frame(width: notch.width)
            claudeLobe.frame(width: IslandMetrics.lobe)
        }
        .frame(height: notch.height)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leftLobe: some View {
        if let e = soonEvent {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.attention)
                Text(e.title ?? "Event").lineLimit(1).font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign))
                Spacer(minLength: 0)
                Text("\(max(0, calendar.minutesToNext() ?? 0))m").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.attention)
            }
            .padding(.horizontal, 12)
        } else {
            HStack(spacing: 8) {
                Record(image: spotify.state.artwork, playing: srcSpotify && spotify.state.playing, size: 18 * IslandMetrics.scale)
                if srcSpotify, spotify.state.hasTrack {
                    Text(spotify.state.name.themed).lineLimit(1).truncationMode(.tail)
                        .font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign))
                        .foregroundStyle(spotify.state.playing ? .white : Palette.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
    }

    /// Label for the most urgent session, then one orb per session.
    private var claudeLobe: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            if let p = claude.primary {
                switch p.phase {
                case .working(let tool, let target):
                    TimelineView(.periodic(from: p.since, by: 4)) { _ in
                        Text(ClaudeState.phrase(tool: tool, target: target, since: p.since).themed).lineLimit(1).truncationMode(.tail)
                    }
                    Elapsed(since: p.since).foregroundStyle(Palette.dim).fixedSize()
                case .done:
                    Text("done · \(p.name)".themed).lineLimit(1).truncationMode(.tail)
                case .permission:
                    Text("needs you · \(p.name)").lineLimit(1).truncationMode(.tail).foregroundStyle(Palette.attention)
                }
            } else {
                Text("idle".themed).foregroundStyle(Palette.dim)
            }
            if claude.sessions.count > 1 { Text("+\(claude.sessions.count - 1)").foregroundStyle(Palette.dim).fixedSize() }
            stateGlyph(claude.primary?.phase, 18 * IslandMetrics.scale)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
    }

    // MARK: - expanded panel

    @ViewBuilder private var panel: some View {
        if let step = tutorial {
            Tutorial(step: step, notchHeight: notch.height, spotify: spotify, next: { tutorial = $0 }, finish: { tutorial = nil; Prefs.hasSeenTutorial = true })
        } else if showSettings {
            quickSettings
        } else if let c = card {
            permissionCard(c)
        } else {
            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case Tab.music: musicTab
                    case Tab.claude: claudeTab
                    case Tab.calendar: calendarTab
                    default: agentTab(tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 18)
                .transition(.opacity)
                tabStrip
            }
            .padding(.top, notch.height + 4)
            .padding(.bottom, 6)
            .foregroundStyle(.white)
            .animation(.easeOut(duration: 0.18), value: tab)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 16) {
            ForEach(tabs, id: \.self) { t in
                switch t {
                case Tab.music: tabButton(t) { SpotifyGlyph(size: 12) }
                case Tab.claude: tabButton(t) { stateGlyph(claudeSessions.first?.phase, 11) }
                case Tab.calendar: tabButton(t) { Image(systemName: "calendar").font(.system(size: 10, weight: .bold)) }
                default: tabButton(t) { Sprite(phase: agentSessions(t).first?.phase, size: 11, tint: agentColor(t)) }
                }
            }
            Button { showAddAgent = true } label: {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.dim).frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Add an AI agent tab")
            .popover(isPresented: $showAddAgent, arrowEdge: .bottom) { addAgentMenu }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                IconButton(soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", size: 10, hit: 22) { soundOn.toggle() }
                    .foregroundStyle(soundOn ? Palette.dim : Palette.attention)
                    .help(soundOn ? "Sounds on" : "Sounds off")
                IconButton("gearshape.fill", size: 10, hit: 22) { showSettings = true }
                    .foregroundStyle(Palette.dim).help("Settings")
            }
            .padding(.trailing, 10)
        }
        .frame(height: 18)
    }

    /// Footer at rest: the current session and model, as a disclosure button. Click for the plan limits.
    private var usageFooter: some View {
        let model = claude.primary?.model.nonEmpty ?? claude.model.nonEmpty
        let text = [claude.primary.map(label), model].compactMap { $0 }.joined(separator: " · ")
        return Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showUsage.toggle() } } label: {
            HStack(spacing: 4) {
                Text(text.isEmpty ? "Plan usage" : text).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(showUsage ? 90 : 0))
            }
            .foregroundStyle(showUsage ? .white : Palette.dim)
            .padding(.horizontal, 6).frame(height: 16)
            .background(showUsage ? Color(white: 0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Plan usage")
    }

    /// Two labelled lines, only when disclosed. Bars live here, where there's room.
    private var usageDetail: some View {
        let u = claude.usage
        return VStack(spacing: 4) {
            limitRow("Session", sub: "5h", u.fiveHour, resets: u.fiveHourResets)
            limitRow("Weekly", sub: "7d", u.sevenDay, resets: u.sevenDayResets)
        }
        .frame(height: IslandMetrics.usageDetailHeight)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func limitRow(_ name: String, sub: String, _ v: Double?, resets: Date?) -> some View {
        let pct = v ?? 0
        let color = limitColor(v)
        return HStack(spacing: 8) {
            (Text(name).foregroundColor(.white) + Text(" · \(sub)").foregroundColor(Palette.dim))
                .font(.system(size: 10, design: .monospaced)).frame(width: 92, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.rule)
                Capsule().fill(color).frame(width: 120 * CGFloat(min(1, pct / 100)))
            }.frame(width: 120, height: 4)
            Text(v.map { "\(Int($0))%" } ?? "—").font(.system(size: 10, weight: .semibold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(color).frame(width: 34, alignment: .trailing)
            Text(resets.map(resetText) ?? (v == nil ? "open the Claude app once" : ""))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.dim).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }

    private func limitColor(_ v: Double?) -> Color {
        guard let v else { return Palette.dim }
        return v >= 95 ? Color(red: 1, green: 0.27, blue: 0.23) : v >= 80 ? Palette.attention : v >= 50 ? .white : Palette.ok
    }

    private func resetText(_ d: Date) -> String {
        let m = Int(d.timeIntervalSinceNow / 60)
        if m < 0 { return "resets soon" }
        if m < 60 { return "\(m)m left" }
        if m < 24 * 60 { return "\(m / 60)h \(m % 60)m left" }
        return "resets " + d.formatted(.dateTime.weekday(.abbreviated))
    }

    private var addAgentMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Add a tab for").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(Prefs.knownAgents.filter { !tabs.contains("agent:" + $0.lowercased()) }, id: \.self) { a in
                Button(a) { Prefs.tabs = tabs + ["agent:" + a.lowercased()]; tab = "agent:" + a.lowercased(); showAddAgent = false }
                    .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }
            Divider().padding(.vertical, 2)
            Button("Manage in Settings…") { showAddAgent = false; SettingsWindow.shared.show() }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
        }
        .font(.system(size: 12)).padding(10).frame(width: 150)
    }

    private func tabButton<G: View>(_ t: String, @ViewBuilder glyph: () -> G) -> some View {
        Button { tab = t; showFull = nil } label: {
            glyph().frame(width: 26, height: 18).contentShape(Rectangle())
                .opacity(tab == t ? 1 : 0.35)
                .overlay(alignment: .bottom) {
                    Capsule().fill(.white).frame(width: 12, height: 2).opacity(tab == t ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TabsEditor.title(t))
    }

    // MARK: quick settings (inside the island; the window has everything)

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Settings").font(.system(size: 13, weight: .semibold, design: Prefs.titleDesign))
                Spacer()
                Button("All settings…") { showSettings = false; SettingsWindow.shared.show() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.attention)
                IconButton("xmark", size: 10, hit: 22) { showSettings = false }
            }
            HStack(spacing: 10) {
                Text("Size").font(.system(size: 11)).foregroundStyle(Palette.dim).frame(width: 60, alignment: .leading)
                ForEach(Array(["Small", "Medium", "Large"].enumerated()), id: \.offset) { i, name in
                    Button(name) { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { size = i } }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(size == i ? .white : Palette.dim)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(size == i ? Color(white: 0.23) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            HStack(spacing: 10) {
                Text("Close after").font(.system(size: 11)).foregroundStyle(Palette.dim).frame(width: 60, alignment: .leading)
                Slider(value: $lingerPref, in: 0...5, step: 0.5).frame(width: 140).controlSize(.mini)
                Text(String(format: "%.1f s", lingerPref)).font(.system(size: 10, design: .monospaced)).monospacedDigit().foregroundStyle(Palette.dim)
            }
            HStack(spacing: 18) {
                quickToggle("Sounds", $soundOn)
                quickToggle("Animation", Binding(get: { !reduceAnimation }, set: { reduceAnimation = !$0 }))
                quickToggle("Pixel worker", $showWorker)
            }
        }
        .padding(.horizontal, 18).padding(.top, notch.height + 6).padding(.bottom, 10)
        .foregroundStyle(.white)
    }

    private func quickToggle(_ name: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: on.wrappedValue ? "checkmark.circle.fill" : "circle").foregroundStyle(on.wrappedValue ? Palette.ok : Palette.dim)
                Text(name).font(.system(size: 11))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: permission card

    private func permissionCard(_ s: ClaudeState.Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .permission(let tool, let detail) = s.phase {
                Text("\(s.name) wants to run").font(.system(size: 15, weight: .semibold, design: Prefs.titleDesign)).foregroundStyle(Palette.attention)
                Text(detail.isEmpty ? tool : detail)
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(2)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.well, in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                Text("\(tool) · \(label(s))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.dim)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Spacer()
                if s.decide == nil {
                    pill("Open Claude", key: nil, fill: Palette.attention, ink: .black) { focus(s) }
                } else {
                    pill("Deny", key: "⎋", fill: Color(white: 0.17), ink: .white) { claude.decide(s.id, allow: false) }
                    pill("Allow", key: "⏎", fill: Palette.attention, ink: .black) { claude.decide(s.id, allow: true) }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, notch.height + 6)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
    }

    private func pill(_ title: String, key: String?, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let key { Text(key).font(.system(size: 10, design: .monospaced)).opacity(0.6) }
            }
            .foregroundStyle(ink).padding(.horizontal, 16).padding(.vertical, 6)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: music

    private var musicTab: some View {
        HStack(alignment: .center, spacing: 14) {
            Record(image: spotify.state.artwork, playing: spotify.state.playing, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(spotify.state.hasTrack ? spotify.state.name : "Nothing playing")
                    .font(.system(size: 13, weight: .semibold, design: Prefs.titleDesign)).lineLimit(1)
                Text(spotify.state.hasTrack ? spotify.state.artist : "Press play in Spotify")
                    .font(.system(size: 11)).foregroundStyle(Palette.dim).lineLimit(1)
                if spotify.state.hasTrack { progress.padding(.top, 2) }
            }
            if spotify.state.hasTrack {
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    IconButton("backward.fill", size: 13, hit: 30) { spotify.previous() }
                    Button { spotify.playPause() } label: {
                        Image(systemName: spotify.state.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 36, height: 36).background(spotify.state.accent, in: Circle())
                    }.buttonStyle(.plain)
                    IconButton("forward.fill", size: 13, hit: 30) { spotify.next() }
                }
            }
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let pos = spotify.state.position(at: ctx.date)
            let dur = spotify.state.duration
            HStack(spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.rule)
                        Capsule().fill(spotify.state.accent).frame(width: g.size.width * (dur > 0 ? pos / dur : 0))
                    }
                    .frame(height: 3).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                        spotify.seek(to: dur * min(1, max(0, v.location.x / g.size.width)))
                    })
                }
                .frame(height: 14)
                Text("\(mmss(pos)) / \(mmss(dur))")
                    .font(.system(size: 10, design: .monospaced)).monospacedDigit().foregroundStyle(Palette.dim)
            }
        }
    }

    // MARK: claude — one row per session

    @ViewBuilder private var claudeTab: some View {
        if let f = showFull, let s = claude.sessions.first(where: { $0.id == f }), case .done(let text) = s.phase {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(s.name).font(.system(size: 13, weight: .semibold, design: Prefs.titleDesign)).foregroundStyle(Palette.ok)
                    Spacer()
                    IconButton("chevron.up", size: 12, hit: 28) { showFull = nil }
                    IconButton("arrow.up.right", size: 12, hit: 28) { focus(s) }
                }
                ScrollView { Text(text).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            }
        } else {
            VStack(spacing: 0) {
                if claudeSessions.isEmpty {
                    Text("Start Claude Code, a Cowork task, or a chat — it shows up here.")
                        .font(.system(size: 11)).foregroundStyle(Palette.dim).frame(maxWidth: .infinity, alignment: .leading).frame(height: IslandMetrics.rowHeight)
                }
                ForEach(claude.ordered.prefix(5)) { sessionRow($0) }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if claudeSessions.count > 5 {
                        Text("+\(claudeSessions.count - 5) more").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.dim)
                    } else if chat.appRunning && !chat.trusted {
                        Text("Chat needs Accessibility").font(.system(size: 10)).foregroundStyle(Palette.dim).lineLimit(1)
                        Button("Allow") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.attention)
                    }
                    Spacer(minLength: 8)
                    usageFooter.layoutPriority(1)
                }
                .frame(height: IslandMetrics.usageHeight)
                if showUsage { usageDetail }
            }
        }
    }

    private func sessionRow(_ s: ClaudeState.Session) -> some View {
        HStack(spacing: 10) {
            stateGlyph(s.phase, 14)
            Group {
                switch s.phase {
                case .working(let tool, let target):
                    TimelineView(.periodic(from: s.since, by: 4)) { _ in
                        (Text(label(s)).font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign))
                         + Text("  \(ClaudeState.phrase(tool: tool, target: target, since: s.since))").font(.system(size: 11)).foregroundColor(Palette.dim))
                    }
                case .done(let text):
                    (Text(label(s)).font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign)).foregroundColor(Palette.ok)
                     + Text("  \(text.split(separator: "\n").first ?? "Done")").font(.system(size: 11)).foregroundColor(Palette.dim))
                case .permission(let tool, _):
                    (Text(label(s)).font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign)).foregroundColor(Palette.attention)
                     + Text("  \(tool)").font(.system(size: 11, design: .monospaced)).foregroundColor(Palette.dim))
                }
            }
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            if s.isWorking { Elapsed(since: s.since).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.dim) }
            if s.isDone { IconButton("chevron.down", size: 10, hit: 22) { showFull = s.id } }
            IconButton("arrow.up.right", size: 10, hit: 22) { focus(s) }
        }
        .frame(height: IslandMetrics.rowHeight)
    }

    private func label(_ s: ClaudeState.Session) -> String {
        switch s.source { case .cowork: "cowork · \(s.name)"; case .chat: "chat · \(s.name)"; case .code: s.name; case .other(let n): "\(n) · \(s.name)" }
    }

    // MARK: agent tabs

    private func agentTab(_ t: String) -> some View {
        let name = String(t.dropFirst(6))
        let rows = agentSessions(t)
        return VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("\(name.capitalized) isn't connected yet").font(.system(size: 13, weight: .semibold, design: Prefs.titleDesign))
                Text("Have it run this when it starts, works, and finishes:").font(.system(size: 11)).foregroundStyle(Palette.dim).padding(.top, 2)
                HStack(spacing: 8) {
                    Text("ProductiveIsland emit --source \(name) --done \"…\"")
                        .font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Palette.well, in: RoundedRectangle(cornerRadius: 6))
                    Button("Copy") {
                        let cmd = Bundle.main.executablePath ?? "ProductiveIsland"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(cmd) emit --source \(name) --session $$ --name \"$(basename \"$PWD\")\" --done \"finished\"", forType: .string)
                    }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.attention)
                }.padding(.top, 6)
                Text("README has the full recipe.").font(.system(size: 10)).foregroundStyle(Palette.dim).padding(.top, 4)
            } else {
                ForEach(rows.prefix(5)) { sessionRow($0) }
            }
        }
    }

    // MARK: calendar

    private var scopedEvents: [EKEvent] {
        switch scope { case .today: calendar.today; case .tomorrow: calendar.tomorrow; case .week: calendar.week }
    }

    private var calendarTab: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(scope == .week ? "This week" : scope.rawValue).font(.system(size: 12, weight: .semibold, design: Prefs.titleDesign))
                IconButton("arrow.up.right", size: 10, hit: 20) { openCalendar(nil) }.help("Open Calendar")
                Spacer()
                HStack(spacing: 2) {
                    ForEach(Scope.allCases, id: \.self) { s in
                        Button(s.rawValue) { scope = s }
                            .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(scope == s ? .white : Palette.dim)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(scope == s ? Color(white: 0.23) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(2).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 6))
            }
            if !calendar.authorized {
                Text("Calendar access is off").font(.system(size: 13, weight: .semibold, design: Prefs.titleDesign))
                Text("Allow Productive Island in System Settings → Privacy → Calendars.").font(.system(size: 11)).foregroundStyle(Palette.dim)
            } else if scope == .week {
                weekList
            } else if let n = scopedEvents.first {
                HStack {
                    Text(n.title ?? "Event").font(.system(size: 13, weight: .semibold, design: Prefs.titleDesign)).lineLimit(1)
                    Spacer()
                    Text(relative(n)).font(.system(size: 11, design: .monospaced)).foregroundStyle(soonEvent == n ? Palette.attention : Palette.dim)
                    IconButton("arrow.up.right", size: 10, hit: 20) { openCalendar(n) }.help("Open in Calendar")
                }
                HStack {
                    Text("\(hhmm(n.startDate)) – \(hhmm(n.endDate))").font(.system(size: 11)).foregroundStyle(Palette.dim)
                    if let u = CalendarFeed.joinURL(n) {
                        Button("Join") { NSWorkspace.shared.open(u) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 3).background(Color(white: 0.2), in: Capsule())
                    }
                }
                Rectangle().fill(Palette.rule).frame(height: 1)
                HStack(spacing: 14) {
                    ForEach(scopedEvents.dropFirst().prefix(2), id: \.eventIdentifier) { e in
                        HStack(spacing: 6) {
                            Text(hhmm(e.startDate)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.dim)
                            Text(e.title ?? "").font(.system(size: 11)).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(scopedEvents.count <= 1 ? "nothing else" : scopedEvents.count > 3 ? "+\(scopedEvents.count - 3) more" : "")
                        .font(.system(size: 10)).foregroundStyle(Palette.dim)
                }
            } else {
                Text(scope == .today ? "Nothing left today" : "Nothing tomorrow").font(.system(size: 13, weight: .semibold, design: Prefs.titleDesign))
                if let t = (scope == .today ? calendar.tomorrow : calendar.week).first {
                    (Text("\(scope == .today ? "Tomorrow" : dayName(t.startDate)) starts with ").foregroundColor(Palette.dim) + Text(t.title ?? "an event") + Text(" at \(hhmm(t.startDate))").foregroundColor(Palette.dim))
                        .font(.system(size: 11))
                } else {
                    Text("Nothing scheduled.").font(.system(size: 11)).foregroundStyle(Palette.dim)
                }
            }
        }
    }

    private var weekList: some View {
        let byDay = Dictionary(grouping: calendar.week) { Calendar.current.startOfDay(for: $0.startDate) }
        let days = byDay.keys.sorted()
        return VStack(alignment: .leading, spacing: 3) {
            if days.isEmpty { Text("Nothing scheduled this week.").font(.system(size: 11)).foregroundStyle(Palette.dim) }
            ForEach(days.prefix(4), id: \.self) { d in
                HStack(spacing: 8) {
                    Text(dayName(d)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.dim).frame(width: 30, alignment: .leading)
                    ForEach((byDay[d] ?? []).prefix(2), id: \.eventIdentifier) { e in
                        Text(hhmm(e.startDate)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.dim)
                        Text(e.title ?? "").font(.system(size: 11)).lineLimit(1)
                    }
                    if (byDay[d]?.count ?? 0) > 2 { Text("+\(byDay[d]!.count - 2)").font(.system(size: 10)).foregroundStyle(Palette.dim) }
                    Spacer(minLength: 0)
                }
                .frame(height: 17)
            }
            if days.count > 4 { Text("+\(days.count - 4) more days").font(.system(size: 10)).foregroundStyle(Palette.dim) }
        }
    }

    /// Calendar.app, jumping to the event when one is given.
    private func openCalendar(_ e: EKEvent?) {
        if let id = e?.calendarItemIdentifier, let u = URL(string: "ical://ekevent/\(id)") { NSWorkspace.shared.open(u); return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    private func relative(_ e: EKEvent) -> String {
        let m = Int(e.startDate.timeIntervalSinceNow / 60)
        if scope == .tomorrow { return "\(dayName(e.startDate)) \(hhmm(e.startDate))" }
        return m < 0 ? "now" : m < 60 ? "in \(m) min" : "in \(m / 60)h \(m % 60)m"
    }
    private func dayName(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated)) }
    private func hhmm(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    private func mmss(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    /// Bring the session's app to the front: the Claude app for Cowork, your terminal for Claude Code.
    private func focus(_ s: ClaudeState.Session) {
        // ponytail: first running app from this list wins; add yours if it's missing.
        if case .other = s.source { return }      // ponytail: unknown app; add a bundle id per source when needed
        let ids = s.source != .code ? ["com.anthropic.claudefordesktop"] : [
            "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
            "com.apple.Terminal", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92" /* Cursor */]
        for id in ids {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { app.activate(); return }
        }
    }
}

extension IslandView {
    @ViewBuilder func stateGlyph(_ phase: ClaudeState.Phase?, _ size: CGFloat) -> some View {
        if showWorker { Sprite(phase: phase, size: size) } else { Orb(phase: phase, size: size * 0.6) }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    /// Pill labels honour the uppercase theme knob.
    var themed: String { Prefs.uppercase ? uppercased() : self }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 11
    var hit: CGFloat = 22
    let action: () -> Void
    init(_ symbol: String, size: CGFloat = 11, hit: CGFloat = 22, action: @escaping () -> Void) {
        self.symbol = symbol; self.size = size; self.hit = hit; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .bold)).frame(width: hit, height: hit).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.white)
    }
}

/// m:ss since a date, ticking once a second.
struct Elapsed: View {
    let since: Date
    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            let s = Int(ctx.date.timeIntervalSince(since))
            Text(String(format: "%d:%02d", s / 60, s % 60)).monospacedDigit()
        }
    }
}

/// Black or glass, flush or floating, with or without a hairline — the theme's surface.
struct IslandSurface: View {
    var radius: CGFloat; var detached: Bool; var glass: Bool; var border: Bool; var compact: Bool
    var body: some View {
        let shape = IslandShape(radius: radius, detached: detached)
        ZStack {
            if glass {
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                shape.fill(.black.opacity(0.55))
            } else {
                shape.fill(.black)
            }
            if border { shape.strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        }
        .shadow(color: .black.opacity(detached ? 0.45 : 0), radius: 10, y: 4)
    }
}

/// Flush against the top bezel, rounded only at the bottom, with small outward curls at the top so it reads as the notch stretching.
/// `detached`: a free capsule, rounded on all four corners, no curls.
struct IslandShape: InsettableShape {
    var radius: CGFloat
    var detached: Bool = false
    var inset: CGFloat = 0
    func inset(by amount: CGFloat) -> IslandShape { var s = self; s.inset += amount; return s }
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        if detached {
            return Path(roundedRect: r, cornerRadius: min(radius, r.height / 2), style: .continuous)
        }
        let curl: CGFloat = min(8, radius / 2)
        let radius = min(radius, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX - curl, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + curl), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.maxY))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + curl))
        p.addQuadCurve(to: CGPoint(x: r.maxX + curl, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}
