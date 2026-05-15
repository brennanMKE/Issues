import SwiftUI
import IssuesCore

/// One row inside `CommandPaletteView`'s result list. Issues show a status
/// dot; view-mode and tab rows show a generic glyph instead. The right edge
/// carries the category label ("Issue" / "View" / "Tab") so users can scan
/// what they're about to invoke.
struct CommandPaletteRowView: View {
    let command: PaletteCommand
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                leadingGlyph
                    .frame(width: 18, alignment: .leading)
                Text(command.displayText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                Text(command.categoryText)
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.appMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.18) : Color.clear)
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch command {
        case .issue(let issue):
            StatusDotView(status: issue.status)
        case .viewMode:
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 13))
                .foregroundStyle(Color.appMuted)
        case .tab:
            Image(systemName: "rectangle.stack")
                .font(.system(size: 13))
                .foregroundStyle(Color.appMuted)
        }
    }
}

#if DEBUG
#Preview("Light") {
    VStack(spacing: 0) {
        CommandPaletteRowView(
            command: .issue(PreviewSamples.issue),
            isSelected: true,
            onTap: {}
        )
        CommandPaletteRowView(
            command: .viewMode(.timeline),
            isSelected: false,
            onTap: {}
        )
    }
    .frame(width: 640)
    .background(Color.appBackground)
    .preferredColorScheme(.light)
}
#endif
