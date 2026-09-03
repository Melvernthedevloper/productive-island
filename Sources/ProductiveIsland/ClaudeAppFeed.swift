import AppKit
import ApplicationServices

/// Chat in the Claude desktop app writes nothing to disk, so we watch its window through Accessibility:
/// the "Stop response" button exists only while a reply is streaming.
/// ponytail: heuristic on the web UI's button label; if Anthropic renames it, change `stopWords`.
@MainActor
final class ClaudeAppFeed {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let stopWords = ["Stop response", "Stop generating", "Stop"]
    private let state: ClaudeState
    private(set) var trusted = AXIsProcessTrusted()
    private var streaming = false
    private var promptedOnce = false
    private var logged = 0
    private static let logURL = URL(fileURLWithPath: (ClaudeFeed.socketPath as NSString).deletingLastPathComponent + "/chat.log")
    private func log(_ m: String) {
        guard logged < 40 else { return }   // ponytail: first 40 lines are enough to see what AX exposes
        logged += 1
        try? (String(data: (try? Data(contentsOf: ClaudeAppFeed.logURL)) ?? Data(), encoding: .utf8)! + "\(Date()) \(m)\n").write(to: ClaudeAppFeed.logURL, atomically: true, encoding: .utf8)
    }

    var appRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeAppFeed.bundleID).isEmpty }

    init(state: ClaudeState) {
        self.state = state
        Task { while !Task.isCancelled { poll(); try? await Task.sleep(for: .milliseconds(1500)) } }
    }

    /// Opens the system prompt once; afterwards the Claude tab shows a hint with a settings link.
    func requestPermission() {
        guard !promptedOnce else { return }
        promptedOnce = true
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    private func poll() {
        guard Prefs.source("chat"), let app = NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeAppFeed.bundleID).first else { return }
        if !trusted { trusted = AXIsProcessTrusted(); if !trusted { log("not trusted"); requestPermission(); return } }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)   // Electron exposes web content only when asked
        var wins: CFTypeRef?
        AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &wins)
        var now = false, title = "Chat"
        let list = (wins as? [AXUIElement]) ?? []
        log("windows: \(list.count) titles: \(list.map { attr($0, kAXTitleAttribute) as? String ?? "?" })")
        for w in list {
            var budget = 4000
            var labels: [String] = []
            collectButtons(w, &labels, 3000)
            log("buttons(\(labels.count)): \(labels.prefix(25))")
            if hasStopButton(w, &budget) {
                now = true
                if let t = attr(w, kAXTitleAttribute) as? String, !t.isEmpty, t != "Claude" { title = t }
                break
            }
        }
        if now != streaming {
            streaming = now
            state.applyChat(streaming: now, title: title)
        }
    }

    private func hasStopButton(_ el: AXUIElement, _ budget: inout Int) -> Bool {
        budget -= 1
        guard budget > 0 else { return false }
        if attr(el, kAXRoleAttribute) as? String == kAXButtonRole {
            let label = [attr(el, kAXDescriptionAttribute), attr(el, kAXTitleAttribute)].compactMap { $0 as? String }.joined(separator: " ")
            if ClaudeAppFeed.stopWords.contains(where: { label.localizedCaseInsensitiveContains($0) }) { return true }
        }
        for c in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] where hasStopButton(c, &budget) { return true }
        return false
    }

    private func collectButtons(_ el: AXUIElement, _ out: inout [String], _ budget: Int) {
        var b = budget
        func walk(_ e: AXUIElement) {
            b -= 1; guard b > 0 else { return }
            if attr(e, kAXRoleAttribute) as? String == kAXButtonRole {
                out.append([attr(e, kAXDescriptionAttribute), attr(e, kAXTitleAttribute)].compactMap { $0 as? String }.joined(separator: "/"))
            }
            for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c) }
        }
        walk(el)
    }

    private func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, name as CFString, &v)
        return v
    }
}
