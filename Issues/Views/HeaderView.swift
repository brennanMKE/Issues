import SwiftUI
import AppKit

/// Top-of-window strip. After the layout overhaul in #0022 the header shows
/// the app icon on the leading edge and the search field on the trailing
/// edge — the long folder path was retired (the per-tab tooltip in
/// `TabBarView` carries that info now). The search field used to live in
/// `ToolbarView` but was moved here so the toolbar row stops fighting for
/// horizontal space with status pills and the module/platform pickers.
struct HeaderView: View {
    @Bindable var store: IssueStore
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            appIcon
            Spacer()
            searchField
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
        }
        .onAppear {
            // Wire the Cmd+F menu shortcut (#0008 stub) to focus this field.
            // The closure captures `_isSearchFocused` (the `@FocusState`
            // projected value), which lives as long as this view's underlying
            // state. We clear the closure on disappear to avoid keeping a
            // dangling capture if the header is torn down. The location of
            // this registration moved from `ToolbarView` to `HeaderView` in
            // #0022; the controller closure pattern is location-agnostic.
            AppCommandsController.shared.focusSearch = {
                isSearchFocused = true
            }
        }
        .onDisappear {
            AppCommandsController.shared.focusSearch = nil
        }
    }

    /// Renders the bundle's app icon at ~22pt. Falls back to a tinted
    /// `tray.full.fill` SF Symbol if the bundle icon can't be resolved (e.g.
    /// in previews or before the asset catalog has been compiled in).
    @ViewBuilder
    private var appIcon: some View {
        if let nsImage = NSImage(named: NSImage.applicationIconName) ?? NSImage(named: "AppIcon") {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 22, height: 22)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.appMuted)

            TextField("Search", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.appText)
                .focused($isSearchFocused)
                .onKeyPress(.escape) {
                    if !store.searchQuery.isEmpty {
                        store.searchQuery = ""
                    }
                    isSearchFocused = false
                    return .handled
                }

            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.appBackgroundCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSearchFocused ? Color.appAccentDim : Color.appBorder, lineWidth: 1)
        )
    }
}
