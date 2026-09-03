import AppKit
import Observation
import SwiftUI

@Observable @MainActor
final class TrackState {
    var name = ""
    var artist = ""
    var playing = false
    var duration: TimeInterval = 0
    var positionAt: (pos: TimeInterval, date: Date) = (0, .distantPast)
    var artwork: NSImage?
    var accent: Color = Color(red: 0x1D/255, green: 0xB9/255, blue: 0x54/255)
    var hasTrack: Bool { !name.isEmpty }

    /// Current position, extrapolated from the last event.
    func position(at date: Date) -> TimeInterval {
        min(duration, positionAt.pos + (playing ? date.timeIntervalSince(positionAt.date) : 0))
    }
}

/// Spotify pushes `com.spotify.client.PlaybackStateChanged` on every change — no polling, no permission.
/// Artwork comes from the public oEmbed endpoint; AppleScript is used only for transport (one Automation grant).
@MainActor
final class SpotifyFeed {
    let state = TrackState()
    private var lastTrackID = ""

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo ?? [:]
            Task { @MainActor in self?.apply(info) }
        }
        // ponytail: Spotify only posts on change, so the lobe stays empty until the next track/pause. No AppleScript at launch = no permission prompt.
    }

    private func apply(_ info: [AnyHashable: Any]) {
        state.name = info["Name"] as? String ?? ""
        state.artist = info["Artist"] as? String ?? ""
        state.playing = (info["Player State"] as? String) == "Playing"
        state.duration = ((info["Duration"] as? Double) ?? 0) / 1000
        state.positionAt = ((info["Playback Position"] as? Double) ?? 0, Date())
        let id = info["Track ID"] as? String ?? ""
        if state.name.isEmpty { state.artwork = nil; lastTrackID = ""; return }
        if id != lastTrackID { lastTrackID = id; Task { await fetchArtwork(id) } }
    }

    private func fetchArtwork(_ trackID: String) async {
        guard let url = URL(string: "https://open.spotify.com/oembed?url=\(trackID)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thumb = obj["thumbnail_url"] as? String, let turl = URL(string: thumb),
              let (img, _) = try? await URLSession.shared.data(from: turl),
              let image = NSImage(data: img) else { return }
        state.artwork = image
        state.accent = SpotifyFeed.dominantColor(image) ?? state.accent
    }

    /// Average colour, then pushed toward saturation so it reads on black.
    nonisolated static func dominantColor(_ image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff),
              let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let c = NSColor(red: CGFloat(px[0])/255, green: CGFloat(px[1])/255, blue: CGFloat(px[2])/255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(NSColor(hue: h, saturation: max(s, 0.55), brightness: max(b, 0.75), alpha: 1))
    }

    // MARK: transport (AppleScript)

    func playPause() { run("playpause") }
    func next() { run("next track") }
    func previous() { run("previous track") }
    func seek(to t: TimeInterval) { run("set player position to \(t)") }

    private func run(_ cmd: String) {
        let src = "tell application \"Spotify\"\n\(cmd)\nend tell"
        Task.detached { _ = NSAppleScript(source: src)?.executeAndReturnError(nil) }
    }
}
