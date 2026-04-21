import SwiftUI
import ClearlyCore

struct RawTextDetailView_iOS: View {
    @Environment(VaultSession.self) private var session

    let file: VaultFile

    @State private var text: String = ""
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: file.id) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView(file.isPlaceholder ? "Downloading from iCloud…" : "Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.orange)
                Text("Couldn't open this note")
                    .font(.headline)
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
        }
    }

    private var footer: some View {
        Text("Read-only preview — editing lands in the next build.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            if file.isPlaceholder {
                try await session.ensureDownloaded(file.url)
            }
            let loaded = try await session.readRawText(at: file.url)
            text = loaded
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
