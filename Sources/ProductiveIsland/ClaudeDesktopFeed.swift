import Foundation

/// Reads what the Claude desktop app already writes to disk: Cowork session audit logs and plan usage samples.
/// ponytail: 1.5 s polling over a handful of files beats FSEvents plumbing; revisit if you run dozens of sessions.
@MainActor
final class ClaudeDesktopFeed {
    static let root = ProcessInfo.processInfo.environment["VIBE_CLAUDE_ROOT"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Claude")
    private let state: ClaudeState
    private var offsets: [String: UInt64] = [:]
    private var current: URL?

    init(state: ClaudeState) {
        self.state = state
        Task {
            while !Task.isCancelled {
                pollCowork(); pollUsage()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    // MARK: cowork

    private func pollCowork() {
        let sessions = ClaudeDesktopFeed.root.appendingPathComponent("local-agent-mode-sessions")
        guard let en = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        var newest: (URL, Date)?
        for case let u as URL in en where u.lastPathComponent == "audit.jsonl" {
            let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if newest == nil || m > newest!.1 { newest = (u, m) }
        }
        guard let (file, mtime) = newest, mtime > Date().addingTimeInterval(-3600) else { return }   // ignore stale sessions
        if file != current { current = file; offsets[file.path] = fileSize(file) }              // start tailing from the end
        guard let fh = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? fh.close() }
        let off = offsets[file.path] ?? 0
        try? fh.seek(toOffset: off)
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return }
        offsets[file.path] = off + UInt64(data.count)
        let (title, model) = sessionMeta(for: file)
        let id = file.deletingLastPathComponent().lastPathComponent
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { state.applyCowork(obj, id: id, title: title, model: model) }
        }
    }

    private func fileSize(_ u: URL) -> UInt64 { (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? UInt64) ?? 0 }

    private func sessionMeta(for audit: URL) -> (String, String) {
        let meta = audit.deletingLastPathComponent().appendingPathExtension("json")
        guard let d = try? Data(contentsOf: meta), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return ("Cowork", "") }
        return (o["title"] as? String ?? "Cowork", ClaudeDesktopFeed.prettyModel(o["model"] as? String ?? ""))
    }

    /// "claude-opus-5" → "Opus 5", "claude-sonnet-4-6" → "Sonnet 4.6"
    nonisolated static func prettyModel(_ id: String) -> String {
        let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
        guard let name = parts.first else { return id }
        let ver = parts.dropFirst().filter { Int($0) != nil }.joined(separator: ".")
        return (name.prefix(1).uppercased() + name.dropFirst()) + (ver.isEmpty ? "" : " " + ver)
    }

    // MARK: usage

    private var usageMtime: Date = .distantPast
    private func pollUsage() {
        let f = ClaudeDesktopFeed.root.appendingPathComponent("plan-usage-history.json")
        let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        guard m > usageMtime, let d = try? Data(contentsOf: f),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let last = (o["samples"] as? [[String: Any]])?.last, let u = last["u"] as? [String: Any] else { return }
        usageMtime = m
        state.usage.fiveHour = u["fh"] as? Double
        state.usage.sevenDay = u["sd"] as? Double
        state.usage.asOf = (last["t"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}
