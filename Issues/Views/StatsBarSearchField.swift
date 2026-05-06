import SwiftUI

/// Extracted so the search field's `@FocusState` and `AppCommandsController`
/// closure registration live in their own view's lifetime — moving the field
/// out of `HeaderView` (#0028) preserves the same pattern: `onAppear` wires
/// `focusSearch` to flip `isSearchFocused`, `onDisappear` clears it.
struct StatsBarSearchField: View {
    @Bindable var store: IssueStore
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.appMuted)

            TextField("Search title, description, or number", text: $store.searchQuery)
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
        .onAppear {
            // Wire the Cmd+F menu shortcut (#0008) to focus this field.
            // Registration moved here from `HeaderView` in #0028; the
            // controller closure pattern is location-agnostic. We clear on
            // disappear so a torn-down view doesn't leave a dangling
            // capture.
            AppCommandsController.shared.focusSearch = {
                isSearchFocused = true
            }
        }
        .onDisappear {
            AppCommandsController.shared.focusSearch = nil
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        StatsBarSearchField(store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        StatsBarSearchField(store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    StatsBarSearchField(store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatsBarSearchField(store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.dark)
}
#endif
