import SwiftUI

/// The signature: five bars. Audio level when music plays, token cadence when Claude thinks, 1px at rest.
struct Bars: View {
    var levels: [CGFloat]      // 0...1, count 5
    var color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 2, height: max(1, 12 * (levels.indices.contains(i) ? levels[i] : 0)))
            }
        }
        .frame(height: 12)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: levels)
    }
}
