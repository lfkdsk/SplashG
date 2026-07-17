import SwiftUI

/// Two-plus-column waterfall. Items are distributed to the currently
/// shortest column using their aspect ratio (w/h), so the columns stay
/// balanced without measuring views.
struct MasonryGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var columns: Int = 2
    var spacing: CGFloat = 12
    let aspect: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    private var distributed: [[Item]] {
        var heights = [CGFloat](repeating: 0, count: columns)
        var result = [[Item]](repeating: [], count: columns)
        for item in items {
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            result[target].append(item)
            heights[target] += 1 / max(aspect(item), 0.1)
        }
        return result
    }

    var body: some View {
        let cols = distributed
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { c in
                LazyVStack(spacing: spacing) {
                    ForEach(cols[c]) { item in
                        content(item)
                    }
                }
            }
        }
    }
}
