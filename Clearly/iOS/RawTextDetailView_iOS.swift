import SwiftUI
import ClearlyCore

struct RawTextDetailView_iOS: View {
    @Environment(VaultSession.self) private var vault
    @Environment(\.scenePhase) private var scenePhase

    let file: VaultFile

    @State private var document = IOSDocumentSession()

    var body: some View {
        VStack(spacing: 0) {
            if document.hasConflict { conflictBanner }
            content
        }
        .navigationTitle(document.isDirty ? "• \(file.name)" : file.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: file.id) {
            await document.open(file, via: vault)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                Task { await document.flush() }
            }
        }
        .onDisappear {
            Task { await document.close() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if document.isLoading {
            ProgressView(file.isPlaceholder ? "Downloading from iCloud…" : "Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = document.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.orange)
                Text("Couldn't open this note")
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EditorView_iOS(text: Binding(
                get: { document.text },
                set: { document.text = $0 }
            ))
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This note has an offline conflict")
                .font(.footnote)
            Spacer()
            Button("Resolve") { }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
    }
}
