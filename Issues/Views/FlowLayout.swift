import SwiftUI

/// Wraps subviews onto multiple rows, like CSS `flex-wrap: wrap`.
/// Variable card widths preclude `LazyVGrid`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = computeLines(maxWidth: maxWidth, subviews: subviews)
        let height = lines.map(\.height).reduce(0) { $0 + $1 }
            + CGFloat(max(lines.count - 1, 0)) * lineSpacing
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let lines = computeLines(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for entry in line.items {
                subviews[entry.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: entry.size.width, height: entry.size.height)
                )
                x += entry.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct LineEntry {
        let index: Int
        let size: CGSize
    }

    private struct Line {
        var items: [LineEntry] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeLines(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let candidateWidth = current.items.isEmpty
                ? size.width
                : current.width + spacing + size.width
            if !current.items.isEmpty && candidateWidth > maxWidth {
                lines.append(current)
                current = Line()
                current.items.append(LineEntry(index: index, size: size))
                current.width = size.width
                current.height = size.height
            } else {
                if !current.items.isEmpty {
                    current.width += spacing
                }
                current.items.append(LineEntry(index: index, size: size))
                current.width += size.width
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty {
            lines.append(current)
        }
        return lines
    }
}
