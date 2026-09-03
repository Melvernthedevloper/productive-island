import SwiftUI

/// Claude's orb: a dot that is the state. Dim breath idle, orbiting arc while thinking, pop + tick on done, 1 Hz pulse when it needs you.
struct Orb: View {
    let phase: ClaudeState.Phase?      // nil = idle
    var size: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false
    @State private var pop = false

    private var color: Color {
        switch phase {
        case nil: Palette.dim
        case .working: Palette.claude
        case .done: Palette.ok
        case .permission: Palette.attention
        }
    }
    private var isWorking: Bool { if case .working = phase { true } else { false } }
    private var isDone: Bool { if case .done = phase { true } else { false } }
    private var needsYou: Bool { if case .permission = phase { true } else { false } }

    var body: some View {
        ZStack {
            Circle().fill(color)
                .frame(width: size, height: size)
                .opacity(phase == nil ? (breathe ? 0.9 : 0.35) : 1)
                .scaleEffect(pop ? 1.4 : 1)
            if isWorking && !reduceMotion {
                Arc().stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size * 1.9, height: size * 1.9)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                    .onDisappear { spin = false }
            }
            if isDone {
                Image(systemName: "checkmark").font(.system(size: size * 0.6, weight: .black)).foregroundStyle(.black)
            }
        }
        .frame(width: size * 1.9, height: size * 1.9)
        .opacity(needsYou && !reduceMotion ? (breathe ? 1 : 0.4) : 1)
        .animation(.easeInOut(duration: needsYou ? 0.5 : 2).repeatForever(autoreverses: true), value: breathe)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pop)
        .onAppear { if !reduceMotion { breathe = true } }
        .onChange(of: isDone) { _, done in
            guard done, !reduceMotion else { return }
            pop = true
            Task { try? await Task.sleep(for: .milliseconds(180)); pop = false }
        }
    }
}

/// 110° open arc, so the orbit reads as a needle rather than a spinner.
struct Arc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(0), endAngle: .degrees(110), clockwise: false)
        return p
    }
}

/// Album art as a record: spins at 33⅓ rpm while playing, coasts to a stop on pause.
struct Record: View {
    let image: NSImage?
    let playing: Bool
    var size: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.15))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            Circle().fill(.black).frame(width: size * 0.18, height: size * 0.18)   // spindle hole
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .rotationEffect(.degrees(angle))
        .onAppear { if playing { start() } }
        .onChange(of: playing) { _, p in p ? start() : stop() }
    }

    private func start() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { angle += 360 }
    }
    private func stop() {
        let rest = angle.truncatingRemainder(dividingBy: 360)
        angle = rest
        withAnimation(.easeOut(duration: 0.8)) { angle = rest + 40 }
    }
}
