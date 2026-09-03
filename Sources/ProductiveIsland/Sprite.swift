import SwiftUI

/// The pixel worker. 12×12 bitmaps, drawn crisp with Canvas. `#` body, `o` eye, `=` keyboard, `*` spark.
/// idle blinks, working types, done cheers, needs-you waves. Colour = state.
struct Sprite: View {
    let phase: ClaudeState.Phase?
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Prefs.reduceAnimation }
    @State private var blink = false

    static let frames: [String: [[String]]] = [
        "idle": [[
            "............",
            "....####....",
            "...######...",
            "..##o##o##..",
            "..########..",
            "..########..",
            "...######...",
            "..#.####.#..",
            "..#.####.#..",
            "....####....",
            "....#..#....",
            "....#..#...."],
        [   "............",
            "....####....",
            "...######...",
            "..########..",
            "..##.##.##..",
            "..########..",
            "...######...",
            "..#.####.#..",
            "..#.####.#..",
            "....####....",
            "....#..#....",
            "....#..#...."]],
        "working": [[
            "............",
            "....####....",
            "...######...",
            "..##o##o##..",
            "..########..",
            "..########..",
            ".#.######.#.",
            ".##.####.##.",
            "..########..",
            ".==========.",
            "....#..#....",
            "....#..#...."],
        [   "............",
            "....####....",
            "...######...",
            "..##o##o##..",
            "..########..",
            ".#########..",
            ".#.######.#.",
            "....####.##.",
            "..########..",
            ".==========.",
            "....#..#....",
            "....#..#...."],
        [   "............",
            "....####....",
            "...######...",
            "..##o##o##..",
            "..########..",
            "..#########.",
            ".#.######.#.",
            ".##.####....",
            "..########..",
            ".==========.",
            "....#..#....",
            "....#..#...."]],
        "done": [[
            ".*........*.",
            ".#..####..#.",
            ".#.######.#.",
            ".###o##o###.",
            "..########..",
            "..########..",
            "...######...",
            "....####....",
            "....####....",
            "....####....",
            "....#..#....",
            "....#..#...."]],
        "waiting": [[
            "..........#.",
            "....####..#.",
            "...######.#.",
            "..##o##o###.",
            "..########..",
            "..########..",
            "...######...",
            "..#.####....",
            "..#.####....",
            "....####....",
            "....#..#....",
            "....#..#...."],
        [   "............",
            "....####....",
            "...######..#",
            "..##o##o##.#",
            "..########.#",
            "..#########.",
            "...######...",
            "..#.####....",
            "..#.####....",
            "....####....",
            "....#..#....",
            "....#..#...."]],
    ]

    private var key: String {
        switch phase {
        case nil: "idle"
        case .working: "working"
        case .done: "done"
        case .permission: "waiting"
        }
    }
    private var color: Color {
        switch phase {
        case nil: Palette.dim
        case .working: Palette.claude
        case .done: Palette.ok
        case .permission: Palette.attention
        }
    }
    /// Frame for a moment in time. Done is a still; idle only blinks.
    private func frameIndex(at t: TimeInterval) -> Int {
        let frames = Sprite.frames[key]!
        if reduceMotion { return 0 }
        switch key {
        case "idle": return blink ? 1 : 0
        case "working": return Int(t * 7) % frames.count
        case "waiting": return Int(t * 2.5) % frames.count
        default: return 0
        }
    }
    /// How often this state needs redrawing. ponytail: done never ticks, idle ticks slowly.
    private var tick: TimeInterval { switch key { case "working": 1.0 / 7; case "waiting": 0.4; default: 3600 } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tick)) { ctx in
            let rows = Sprite.frames[key]![frameIndex(at: ctx.date.timeIntervalSinceReferenceDate)]
            Canvas { g, sz in
                let px = sz.width / 12
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." {
                        let r = CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px).insetBy(dx: -0.25, dy: -0.25)
                        let c: Color = switch ch { case "o": .black; case "=": Palette.dim; case "*": Palette.attention; default: color }
                        g.fill(Path(r), with: .color(c))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        // idle: a blink every few seconds costs two redraws, not a timer.
        .task(id: key) {
            guard key == "idle", !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2)); blink = true
                try? await Task.sleep(for: .milliseconds(150)); blink = false
            }
        }
        .animation(.easeOut(duration: 0.2), value: key)
        .accessibilityLabel(key)
    }
}

/// `--sprites out.png` renders every frame, scaled up, for checking the art.
@MainActor
enum SpriteSheet {
    static func render(to path: String) {
        let view = HStack(spacing: 12) {
            ForEach(["idle", "working", "done", "waiting"], id: \.self) { k in
                VStack(spacing: 8) {
                    ForEach(Sprite.frames[k]!.indices, id: \.self) { i in
                        Sprite.still(k, i).frame(width: 96, height: 96)
                    }
                    Text(k).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white)
                }
            }
        }
        .padding(16).background(.black)
        let r = ImageRenderer(content: view); r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

extension SpriteSheet {
    /// App icon: the working sprite on a black rounded tile. `--icon out.png` (1024²).
    static func renderIcon(to path: String) {
        let view = ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous).fill(.black)
            Sprite.still("working", 0).frame(width: 640, height: 640)
        }
        .frame(width: 1024, height: 1024)
        let r = ImageRenderer(content: view); r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

extension Sprite {
    /// One fixed frame, for the sheet.
    static func still(_ key: String, _ i: Int) -> some View {
        let color: Color = switch key { case "working": Palette.claude; case "done": Palette.ok; case "waiting": Palette.attention; default: Palette.dim }
        let rows = frames[key]![i]
        return Canvas { g, sz in
            let px = sz.width / 12
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    let c: Color = switch ch { case "o": .black; case "=": Palette.dim; case "*": Palette.attention; default: color }
                    g.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(c))
                }
            }
        }
    }
}
