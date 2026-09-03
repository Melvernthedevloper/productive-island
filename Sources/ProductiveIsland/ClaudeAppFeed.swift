import AppKit
import ApplicationServices

/// Chat in the Claude desktop app writes nothing to disk, so we watch its window through Accessibility:
/// the "Stop response" button exists only while a reply is streaming.
/// ponytail: heuristic on the web UI's button label; if Anthropic renames it, change `stopWords`.
@MainActor
final class ClaudeAppFeed {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let stopWords = ["Stop response", "Stop generating", "Stop"]
    private static let allowWords = ["Allow once", "Allow always", "Always allow", "Allow for this chat", "Allow"]
    private static let denyWords = ["Deny", "Don't allow", "Decline", "Reject"]
    private var prompt: (allow: AXUIElement, deny: AXUIElement?)?
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
        var found: (AXUIElement, AXUIElement?)? = nil
        for w in list {
            var budget = 4000
            var labels: [String] = []
            collectButtons(w, &labels, 3000)
            log("buttons(\(labels.count)): \(labels.prefix(25))")
            if found == nil { found = permissionButtons(w) }
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
        // A permission sheet (MCP tool, file access…) shows Allow/Deny buttons; the island can press them.
        if let f = found, prompt == nil {
            prompt = f
            let allow = f.0, deny = f.1
            state.applyChatPermission(title: title, detail: buttonContext(allow)) { ok in
                AXUIElementPerformAction(ok ? allow : (deny ?? allow), kAXPressAction as CFString)
            }
        } else if found == nil, prompt != nil {
            prompt = nil
            state.clearChatPermission()
        }
    }

    /// (allow, deny) buttons if a permission sheet is up. ponytail: label match; extend the word lists if Anthropic rewords.
    private func permissionButtons(_ el: AXUIElement) -> (AXUIElement, AXUIElement?)? {
        var allow: AXUIElement?, deny: AXUIElement?, budget = 4000
        func walk(_ e: AXUIElement) {
            budget -= 1; guard budget > 0, allow == nil || deny == nil else { return }
            if attr(e, kAXRoleAttribute) as? String == kAXButtonRole {
                let label = [attr(e, kAXDescriptionAttribute), attr(e, kAXTitleAttribute)].compactMap { $0 as? String }.joined(separator: " ")
                if allow == nil, ClaudeAppFeed.allowWords.contains(where: { label.caseInsensitiveCompare($0) == .orderedSame || label.localizedCaseInsensitiveContains($0 + " ") }) { allow = e }
                else if deny == nil, ClaudeAppFeed.denyWords.contains(where: { label.localizedCaseInsensitiveContains($0) }) { deny = e }
            }
            for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c) }
        }
        walk(el)
        guard let a = allow, deny != nil else { return nil }     // both present = a real prompt, not a stray "Allow" in text
        return (a, deny)
    }

    /// Nearby static text, so the card can say what is being asked.
    private func buttonContext(_ button: AXUIElement) -> String {
        var parent: CFTypeRef?
        AXUIElementCopyAttributeValue(button, kAXParentAttribute as CFString, &parent)
        guard let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() else { return "" }
        var texts: [String] = []
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard depth < 4, texts.count < 6 else { return }
            if attr(e, kAXRoleAttribute) as? String == kAXStaticTextRole, let v = attr(e, kAXValueAttribute) as? String, !v.isEmpty { texts.append(v) }
            for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, depth + 1) }
        }
        var grand: CFTypeRef?
        AXUIElementCopyAttributeValue(p as! AXUIElement, kAXParentAttribute as CFString, &grand)
        walk((grand as! AXUIElement?) ?? (p as! AXUIElement), 0)
        return texts.joined(separator: " · ")
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
