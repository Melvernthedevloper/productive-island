import SwiftUI

/// The signature: five bars. Audio level when music plays, token cadence when Claude thinks, 1px at rest.
struct Bars: View {
    var levels: [CGFloat]      // 0...1, count 5
    var color: Color
    var thick: Bool = Prefs.thickBars

    var body: some View {
        HStack(alignment: .center, spacing: thick ? 3 : 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: thick ? 0 : 1)
                    .fill(color)
                    .frame(width: thick ? 4 : 2, height: max(thick ? 2 : 1, 12 * (levels.indices.contains(i) ? levels[i] : 0)))
            }
        }
        .frame(height: 12)
        .animation(Prefs.reduceAnimation ? nil : .spring(response: 0.18, dampingFraction: 0.6), value: levels)
    }
}
