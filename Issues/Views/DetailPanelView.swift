import SwiftUI
import AppKit
import Textual

struct DetailPanelView: View {
    let issue: Issue
    let onClose: () -> Void
    let onOpenMarkdown: (Issue) -> Void

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                header
                metadata
                Divider().background(Color.appBorder)
                description
                fileLink
            }
            .padding(16)
        }
        .background(Color.appBackgroundCard)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(issue.id)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.appMuted)
                Text(issue.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.appMuted)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                label("Status")
                StatusBadgeView(status: issue.status)
            }
            GridRow {
                label("Module")
                Text(issue.module.isEmpty ? "\u{2014}" : issue.module)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appText)
            }
            GridRow {
                label("Platform")
                Text(issue.platform.isEmpty ? "\u{2014}" : issue.platform)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appText)
            }
            GridRow {
                label("Filed")
                Text(formatted(issue.firstSeen, raw: issue.firstSeenRaw))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appText)
            }
            if !issue.closedRaw.isEmpty {
                GridRow {
                    label("Closed")
                    Text(formatted(issue.closed, raw: issue.closedRaw))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appText)
                }
            }
        }
    }

    private var description: some View {
        Group {
            if let body = bodyMarkdown() {
                StructuredText(
                    markdown: body,
                    baseURL: issue.fileURL.deletingLastPathComponent()
                )
                .textual.textSelection(.enabled)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !issue.description.isEmpty {
                Text(issue.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No description")
                    .font(.system(size: 12, weight: .regular))
                    .italic()
                    .foregroundStyle(Color.appMuted)
            }
        }
    }

    /// Returns the markdown body below the H1 title and metadata table,
    /// starting at the first H2 (`## `). Returns nil if the file can't be
    /// read or no H2 is found, so callers can fall back to plain text.
    private func bodyMarkdown() -> String? {
        guard let raw = try? String(contentsOf: issue.fileURL, encoding: .utf8) else {
            return nil
        }
        guard let range = raw.range(of: "\n## ") else {
            return nil
        }
        // Include the H2 marker itself; drop the leading newline.
        let body = raw[range.lowerBound...].dropFirst()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var fileLink: some View {
        Button {
            onOpenMarkdown(issue)
        } label: {
            HStack(spacing: 4) {
                Text("\(issue.id).md")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.appAccent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Preview \(issue.fileURL.lastPathComponent)")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.appMuted)
            .gridColumnAlignment(.leading)
    }

    private func formatted(_ date: Date?, raw: String) -> String {
        if let date {
            return Self.displayDateFormatter.string(from: date)
        }
        return raw.isEmpty ? "\u{2014}" : raw
    }
}
