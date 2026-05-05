import SwiftUI

// MARK: - Display item

/// One slot in the HStack while rendering. Either a real tab (rendered as
/// a `TabChipView`, or a transparent ghost when it's the one being
/// dragged) or the transparent placeholder that marks the phantom slot.
struct DisplayItem: Identifiable {
    let id: AnyHashable
    let kind: Kind

    enum Kind {
        case tab(IssueStore)
        case placeholder
    }
}
