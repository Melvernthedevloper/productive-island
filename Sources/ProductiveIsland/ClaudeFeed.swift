import Foundation
import Network
import Observation

@Observable @MainActor
final class ClaudeState {
    enum Phase: Equatable {
        case working(tool: String, target: String)
        case done(String)
        case permission(tool: String, detail: String)
    }
    enum Source { case code, cowork, chat }

    struct Session: Identifiable {
        let id: String
        var source: Source
        var name: String
        var model = ""
        var phase: Phase
        var since = Date()
        var lastEvent = Date()
        var decide: ((Bool) -> Void)?      // answers a Claude Code PermissionRequest hook
        var isWorking: Bool { if case .working = phase { true } else { false } }
        var isDone: Bool { if case .done = phase { true } else { false } }
        var needsYou: Bool { if case .permission = phase { true } else { false } }
        var urgency: Int { needsYou ? 0 : isDone && lastEvent > Date().addingTimeInterval(-6) ? 1 : isWorking ? 2 : 3 }
    }

    struct Usage: Equatable {
        var fiveHour: Double?; var sevenDay: Double?; var context: Double?; var asOf: Date?
        var fiveHourResets: Date?; var sevenDayResets: Date?
    }
    var usage = Usage()
    var sessions: [Session] = []
    var model = ""                       // last model seen from the statusline

    /// Most urgent first, then most recent.
    var ordered: [Session] { sessions.sorted { ($0.urgency, $1.lastEvent) < ($1.urgency, $0.lastEvent) } }
    var primary: Session? { ordered.first }
    var anyWorking: Bool { sessions.contains { $0.isWorking } }
    var waiting: Session? { ordered.first { $0.needsYou } }

    private func upsert(_ id: String, source: Source, name: String, _ change: (inout Session) -> Void) {
        if let i = sessions.firstIndex(where: { $0.id == id }) {
            let was = sessions[i].isWorking
            change(&sessions[i])
            sessions[i].lastEvent = Date()
            if !was && sessions[i].isWorking { sessions[i].since = Date() }
        } else {
            var s = Session(id: id, source: source, name: name, model: source == .code ? model : "", phase: .working(tool: "thinking", target: ""))
            change(&s)
            sessions.append(s)
        }
    }

    func remove(_ id: String) { sessions.removeAll { $0.id == id } }

    /// Done rows linger 10 min; silent working rows drop after 30 min.
    func prune() {
        let now = Date()
        sessions.removeAll { ($0.isDone && $0.lastEvent < now - 600) || ($0.isWorking && $0.lastEvent < now - 1800) }
    }

    func decide(_ id: String, allow: Bool) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].decide?(allow)
        sessions[i].decide = nil
        sessions[i].phase = .working(tool: allow ? "thinking" : "denied", target: "")
    }

    // MARK: Claude Code hooks (and the statusline payload)

    func apply(_ e: [String: Any], decide: ((Bool) -> Void)? = nil) {
        let id = e["session_id"] as? String ?? "code"
        if let cw = e["context_window"] as? [String: Any] {   // statusline payload, not a hook
            let rl = e["rate_limits"] as? [String: Any] ?? [:]
            func pct(_ k: String) -> Double? { ((rl[k] as? [String: Any])?["used_percentage"] as? Double) }
            func resets(_ k: String) -> Date? {
                let r = (rl[k] as? [String: Any])?["resets_at"]
                if let n = r as? Double { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
                if let str = r as? String { return ISO8601DateFormatter().date(from: str) }
                return nil
            }
            if let f = pct("five_hour") { usage.fiveHour = f; usage.asOf = Date(); usage.fiveHourResets = resets("five_hour") }
            if let s = pct("seven_day") { usage.sevenDay = s; usage.sevenDayResets = resets("seven_day") }
            usage.context = cw["used_percentage"] as? Double
            if let m = (e["model"] as? [String: Any])?["display_name"] as? String {
                model = m
                if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].model = m }
            }
            return
        }
        let name = ((e["cwd"] as? String ?? "") as NSString).lastPathComponent
        switch e["hook_event_name"] as? String ?? "" {
        case "SessionStart", "UserPromptSubmit", "PostToolUse":
            upsert(id, source: .code, name: name) { $0.phase = .working(tool: "thinking", target: "") }
        case "PreToolUse":
            let input = e["tool_input"] as? [String: Any] ?? [:]
            upsert(id, source: .code, name: name) { $0.phase = .working(tool: e["tool_name"] as? String ?? "tool", target: ClaudeState.target(input)) }
        case "PermissionRequest":
            let input = e["tool_input"] as? [String: Any] ?? [:]
            upsert(id, source: .code, name: name) {
                $0.phase = .permission(tool: e["tool_name"] as? String ?? "tool", detail: ClaudeState.detail(input))
                $0.decide = decide
            }
        case "Stop":
            let text = ClaudeState.lastAssistantText(e["transcript_path"] as? String)
            upsert(id, source: .code, name: name) { $0.phase = .done(text) }
        case "SessionEnd":
            remove(id)
        default: break
        }
    }

    // MARK: Cowork audit.jsonl

    func applyCowork(_ o: [String: Any], id: String, title: String, model: String) {
        switch o["type"] as? String {
        case "user":
            upsert(id, source: .cowork, name: title) { $0.model = model; $0.phase = .working(tool: "thinking", target: "") }
        case "assistant":
            let content = (o["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            guard let tu = content.first(where: { $0["type"] as? String == "tool_use" }) else { return }
            let name = (tu["name"] as? String ?? "tool").replacingOccurrences(of: "mcp__cowork__", with: "")
            upsert(id, source: .cowork, name: title) { $0.model = model; $0.phase = .working(tool: name, target: ClaudeState.target(tu["input"] as? [String: Any] ?? [:])) }
        case "system" where o["subtype"] as? String == "permission_request":
            upsert(id, source: .cowork, name: title) { $0.phase = .permission(tool: o["tool_name"] as? String ?? "a tool", detail: ClaudeState.detail(o["tool_input"] as? [String: Any] ?? [:])) }
        case "result":
            upsert(id, source: .cowork, name: title) { $0.phase = .done((o["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Done") }
        default: break
        }
    }

    // MARK: Claude app chat (Accessibility)

    func applyChat(streaming: Bool, title: String) {
        if streaming {
            upsert("chat", source: .chat, name: title) { $0.phase = .working(tool: "writing", target: "") }
        } else if sessions.contains(where: { $0.id == "chat" }) {
            upsert("chat", source: .chat, name: title) { $0.phase = .done("Reply finished in the Claude app.") }
        }
    }

    // MARK: wording

    /// What to say while a tool runs — a verb people recognise, not the tool's internal name.
    nonisolated static func phrase(tool: String, target: String, since: Date) -> String {
        let t = target.isEmpty ? "" : " " + target
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing" + t
        case "Read": return "Reading" + t
        case "Bash": return "Running" + (target.isEmpty ? " a command" : " " + firstWords(target))
        case "Grep", "Glob", "LS": return "Searching" + (target.isEmpty ? "" : " for " + target)
        case "Task", "Agent": return "Delegating a subtask"
        case "WebFetch", "WebSearch": return "Looking it up online"
        case "TodoWrite": return "Planning the steps"
        case "writing": return "Writing a reply"
        case "denied": return "Denied — waiting"
        case "thinking":
            // ponytail: a slow rotation so long thinks don't look frozen; edit the list to taste.
            let lines = ["Thinking…", "Reading the code", "Connecting the dots", "Weighing options", "Working it out"]
            return lines[Int(Date().timeIntervalSince(since) / 4) % lines.count]
        default: return tool.hasPrefix("mcp__") ? "Using " + tool.split(separator: "_").last.map(String.init)!.replacingOccurrences(of: "_", with: " ") : tool + t
        }
    }
    nonisolated static func firstWords(_ cmd: String) -> String {
        let clean = cmd.replacingOccurrences(of: #"^(\w+=\S+;?\s*)+"#, with: "", options: .regularExpression)   // drop leading VAR=… assignments
        let words = clean.split(separator: " ").prefix(3).joined(separator: " ")
        return words.count > 28 ? String(words.prefix(28)) + "…" : words
    }

    // MARK: helpers

    nonisolated static func target(_ input: [String: Any]) -> String {
        (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
            ?? (input["command"] as? String).map { String(firstWords($0).prefix(40)) }
            ?? input["pattern"] as? String ?? ""
    }
    nonisolated static func detail(_ input: [String: Any]) -> String {
        input["command"] as? String ?? input["file_path"] as? String ?? input["pattern"] as? String
            ?? (try? JSONSerialization.data(withJSONObject: input)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Last assistant message text from the session transcript (JSONL).
    nonisolated static func lastAssistantText(_ path: String?) -> String {
        guard let path, let data = FileManager.default.contents(atPath: path),
              let s = String(data: data, encoding: .utf8) else { return "Done" }
        for line in s.split(separator: "\n").reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            if !text.isEmpty { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return "Done"
    }
}

/// Unix-socket listener. Hooks pipe their stdin JSON in with `nc -U`; one JSON object per connection.
/// PermissionRequest connections stay open until the island answers (or the hook's own timeout fires).
final class ClaudeFeed: @unchecked Sendable {
    static let socketPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProductiveIsland")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sock").path
    }()

    private var listener: NWListener?
    private let onEvent: @Sendable ([String: Any], NWConnection) -> Void

    init(onEvent: @escaping @Sendable ([String: Any], NWConnection) -> Void) throws {
        self.onEvent = onEvent
        unlink(ClaudeFeed.socketPath)
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: ClaudeFeed.socketPath)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            self?.read(conn, buffer: Data())
        }
        l.start(queue: .main)
        listener = l
    }

    private func read(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] chunk, _, complete, _ in
            var buf = buffer
            if let chunk { buf.append(chunk) }
            if let obj = try? JSONSerialization.jsonObject(with: buf) as? [String: Any] {
                self?.onEvent(obj, conn)
                if obj["hook_event_name"] as? String != "PermissionRequest" { conn.cancel() }   // closing makes `nc` exit
            } else if complete {
                conn.cancel()
            } else {
                self?.read(conn, buffer: buf)
            }
        }
    }

    /// Reply to a waiting PermissionRequest hook, then close so `nc` prints it and exits.
    static func answer(_ conn: NWConnection, allow: Bool) {
        let decision: [String: Any] = allow ? ["behavior": "allow"] : ["behavior": "deny", "message": "Denied from Productive Island"]
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        let data = (try? JSONSerialization.data(withJSONObject: out)) ?? Data()
        conn.send(content: data + Data("\n".utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Append our hooks to ~/.claude/settings.json. Idempotent.
    static func installHooks() throws {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/settings.json")
        var root = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let sock = "\"$HOME/Library/Application Support/ProductiveIsland/sock\""
        let fire = "nc -U \(sock) -w 1 2>/dev/null; exit 0"
        let wait = "nc -U \(sock) -w 60 2>/dev/null; exit 0"     // stays open for the island's answer
        func add(_ ev: String, _ cmd: String, timeout: Int) {
            var list = hooks[ev] as? [[String: Any]] ?? []
            list.removeAll { (($0["hooks"] as? [[String: Any]])?.first?["command"] as? String)?.contains("ProductiveIsland/sock") == true }
            list.append(["hooks": [["type": "command", "command": cmd, "timeout": timeout]]])
            hooks[ev] = list
        }
        for ev in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"] { add(ev, fire, timeout: 2) }
        add("PermissionRequest", wait, timeout: 65)
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        print("hooks installed → \(url.path)")
    }
}
