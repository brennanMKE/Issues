import SwiftUI

#if os(macOS)
import AppKit
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "AccessTokenListView")

/// Token management section inside the host settings sheet (#0084).
/// Lists existing tokens, surfaces last-used info, and hosts the
/// inline-confirm revoke flow. The Generate button presents the
/// `GenerateTokenSheet` for minting + one-time plaintext reveal.
struct AccessTokenListView: View {

    @State private var records: [TokenRecord] = []
    @State private var loadError: String?
    @State private var pendingRevokeHash: Data?
    @State private var showingGenerateSheet: Bool = false
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if records.isEmpty {
                Text("No access tokens yet. Generate one to let a viewer connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                tokenRows
            }

            HStack {
                Spacer()
                Button {
                    showingGenerateSheet = true
                } label: {
                    Label("Generate token", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingGenerateSheet) {
            GenerateTokenSheet { _ in
                reload()
            }
        }
        .onAppear {
            reload()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
    }

    private var tokenRows: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Created").frame(width: 90, alignment: .leading)
                Text("Last used").frame(width: 90, alignment: .leading)
                Text("Expires").frame(width: 90, alignment: .leading)
                Text("").frame(width: 60, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)

            ForEach(sorted(records), id: \.hash) { record in
                row(for: record)
            }
        }
    }

    @ViewBuilder
    private func row(for record: TokenRecord) -> some View {
        HStack {
            Text(record.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shortDate(record.createdAt))
                .frame(width: 90, alignment: .leading)
            Text(record.lastUsedAt.map(shortDate) ?? "—")
                .frame(width: 90, alignment: .leading)
            Text(record.expiresAt.map(shortDate) ?? "never")
                .frame(width: 90, alignment: .leading)
            if pendingRevokeHash == record.hash {
                HStack(spacing: 4) {
                    Button("Cancel") {
                        pendingRevokeHash = nil
                    }
                    .controlSize(.small)
                    Button("Confirm") {
                        revoke(record)
                    }
                    .controlSize(.small)
                    .tint(.red)
                }
            } else {
                Button("Revoke") {
                    pendingRevokeHash = record.hash
                }
                .controlSize(.small)
                .frame(width: 60, alignment: .trailing)
            }
        }
        .font(.callout)
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private func reload() {
        do {
            records = try AccessToken.list()
            loadError = nil
        } catch {
            loadError = "Failed to read tokens: \(error.localizedDescription)"
            logger.warning("token list failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func revoke(_ record: TokenRecord) {
        do {
            try AccessToken.revoke(hash: record.hash)
            pendingRevokeHash = nil
            reload()
        } catch {
            loadError = "Revoke failed: \(error.localizedDescription)"
            logger.warning("token revoke failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sorted(_ list: [TokenRecord]) -> [TokenRecord] {
        list.sorted { a, b in
            switch (a.lastUsedAt, b.lastUsedAt) {
            case let (.some(lhs), .some(rhs)):
                return lhs > rhs
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.createdAt > b.createdAt
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in reload() }
        }
        refreshTimer = timer
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Formatting

    private func shortDate(_ date: Date) -> String {
        Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

#endif
