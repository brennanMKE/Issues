import SwiftUI

#if os(macOS)
import AppKit
import os.log

nonisolated private let sheetLogger = Logger(subsystem: Logging.subsystem, category: "GenerateTokenSheet")

/// Modal that mints a new access token (#0084). Two phases:
/// 1. Form: name + expiration choice.
/// 2. Reveal: shows the plaintext exactly once. Closing the sheet
///    discards the plaintext — the user must revoke + regenerate to
///    recover.
///
/// `onTokenCreated` fires after Done so the parent list can refresh.
struct GenerateTokenSheet: View {

    enum ExpirationChoice: Hashable, CaseIterable {
        case never
        case thirtyDays
        case ninetyDays
        case specific

        var label: String {
            switch self {
            case .never: return "Never (default)"
            case .thirtyDays: return "30 days"
            case .ninetyDays: return "90 days"
            case .specific: return "On a specific date"
            }
        }

        func resolved(specificDate: Date) -> Date? {
            switch self {
            case .never: return nil
            case .thirtyDays: return Date(timeIntervalSinceNow: 30 * 24 * 3600)
            case .ninetyDays: return Date(timeIntervalSinceNow: 90 * 24 * 3600)
            case .specific: return specificDate
            }
        }
    }

    let onTokenCreated: (TokenRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var expiration: ExpirationChoice = .never
    @State private var specificDate: Date = Date(timeIntervalSinceNow: 30 * 24 * 3600)
    @State private var revealedPlaintext: String?
    @State private var lastError: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let plaintext = revealedPlaintext {
                revealView(plaintext: plaintext)
            } else {
                formView
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520)
        .onAppear { nameFocused = true }
    }

    // MARK: - Form phase

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate access token")
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.callout)
                TextField("e.g. MacBook Air", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Expires")
                    .font(.callout)
                Picker("Expires", selection: $expiration) {
                    ForEach(ExpirationChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if expiration == .specific {
                    DatePicker(
                        "Date",
                        selection: $specificDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .padding(.leading, 22)
                }
            }

            if let error = lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Generate") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func generate() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let expiresAt = expiration.resolved(specificDate: specificDate)
        do {
            let result = try AccessToken.generate(name: trimmed, expiresAt: expiresAt)
            revealedPlaintext = result.plaintext
            lastError = nil
            onTokenCreated(result.record)
        } catch {
            lastError = error.localizedDescription
            sheetLogger.warning("token generate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reveal phase

    private func revealView(plaintext: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token created")
                .font(.title3)

            Text(plaintext)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.3))
                )

            HStack {
                Button("Copy") { copyToPasteboard(plaintext) }
                Spacer()
            }

            Text("Save this now — it won't be shown again. Paste it into Issues.app on the viewer.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

#endif
