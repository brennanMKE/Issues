import SwiftUI

#if os(macOS)

/// Section content for the host settings sheet (#0092). Shows one row per
/// active peer with the token name, remote address, and (eventually, with
/// #0100) the subscribed-folder list. Until WebSocket subscriptions land,
/// short HTTP requests rarely appear here — the spec accepts that
/// trade-off in exchange for not flickering on every single REST hit.
struct ConnectedViewersListView: View {

    @Bindable var controller: RemoteHostController

    var body: some View {
        let peers = controller.connectedPeers.sorted { $0.connectedAt < $1.connectedAt }
        VStack(alignment: .leading, spacing: 4) {
            if peers.isEmpty {
                Text("No viewers connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Token").frame(width: 140, alignment: .leading)
                    Text("Address").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Subscribed").frame(width: 160, alignment: .leading)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

                ForEach(peers, id: \.connectedAt) { peer in
                    HStack {
                        Text(peer.tokenName ?? "—")
                            .frame(width: 140, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(peer.remoteAddress)
                            .font(.system(.callout, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        // Subscribed folders will be populated once
                        // WebSocket subscriptions land (#0100). Today
                        // every peer reports an empty list.
                        Text("—")
                            .foregroundStyle(.secondary)
                            .frame(width: 160, alignment: .leading)
                    }
                    .font(.callout)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

#endif
