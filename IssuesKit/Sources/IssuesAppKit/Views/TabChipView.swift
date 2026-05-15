import SwiftUI
import IssuesCore

// MARK: - Tab chip

struct TabChipView: View {
    @Bindable var store: IssueStore
    let isActive: Bool
    let hasUnseen: Bool
    let isOnlyTab: Bool
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onRevealInFinder: () -> Void
    let onReload: () -> Void

    @State private var isHovered: Bool = false

    /// Active tab never shows the dot, even if `hasUnseen` somehow lingers.
    private var showsUnseenDot: Bool { hasUnseen && !isActive }

    var body: some View {
        HStack(spacing: 6) {
            // Reserve the dot slot so the chip width doesn't jump when the
            // indicator appears/disappears.
            ZStack {
                if showsUnseenDot {
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 6, height: 6)
                } else {
                    Color.clear.frame(width: 6, height: 6)
                }
            }

            folderGlyph

            if isRemoteTab {
                remoteIndicator
            }

            Text(store.displayName)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(Color.appText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            // Reserve the close-button slot so the chip width doesn't jump on
            // hover. Hidden when not hovering and not active.
            ZStack {
                if isHovered || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.appMuted)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.appAccent.opacity(0.15) : Color.appBackgroundCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.appAccent : Color.appBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
        .accessibilityLabel(accessibilityText)
        .contextMenu {
            Button("Close") { onClose() }
            Button("Close Other Tabs") { onCloseOthers() }
                .disabled(isOnlyTab)
            Divider()
            Button("Reveal in Finder") { onRevealInFinder() }
            Button("Reload") { onReload() }
        }
    }

    private var folderGlyph: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 10))
            .foregroundStyle(isActive ? Color.appAccent : Color.appMuted)
    }

    private var remoteIndicator: some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: 9))
            .foregroundStyle(isActive ? Color.appAccent : Color.appMuted)
            .help("Remote folder")
            .accessibilityLabel("Remote folder")
    }

    private var isRemoteTab: Bool {
        store.folderURL.scheme == RemoteHostIssueSource.urlScheme
    }

    private var helpText: String {
        if showsUnseenDot {
            return "\(store.folderURL.path) — Updated since last viewed"
        }
        return store.folderURL.path
    }

    private var accessibilityText: String {
        if showsUnseenDot {
            return "\(store.displayName), updated since last viewed"
        }
        return store.displayName
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        VStack(spacing: 8) {
            TabChipView(
                store: PreviewSamples.makeStore(),
                isActive: true,
                hasUnseen: false,
                isOnlyTab: false,
                onClose: {},
                onCloseOthers: {},
                onRevealInFinder: {},
                onReload: {}
            )
            TabChipView(
                store: PreviewSamples.makeStore(),
                isActive: false,
                hasUnseen: true,
                isOnlyTab: false,
                onClose: {},
                onCloseOthers: {},
                onRevealInFinder: {},
                onReload: {}
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .light)

        VStack(spacing: 8) {
            TabChipView(
                store: PreviewSamples.makeStore(),
                isActive: true,
                hasUnseen: false,
                isOnlyTab: false,
                onClose: {},
                onCloseOthers: {},
                onRevealInFinder: {},
                onReload: {}
            )
            TabChipView(
                store: PreviewSamples.makeStore(),
                isActive: false,
                hasUnseen: true,
                isOnlyTab: false,
                onClose: {},
                onCloseOthers: {},
                onRevealInFinder: {},
                onReload: {}
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    TabChipView(
        store: PreviewSamples.makeStore(),
        isActive: true,
        hasUnseen: false,
        isOnlyTab: false,
        onClose: {},
        onCloseOthers: {},
        onRevealInFinder: {},
        onReload: {}
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    TabChipView(
        store: PreviewSamples.makeStore(),
        isActive: true,
        hasUnseen: false,
        isOnlyTab: false,
        onClose: {},
        onCloseOthers: {},
        onRevealInFinder: {},
        onReload: {}
    )
    .padding()
    .preferredColorScheme(.dark)
}
#endif
