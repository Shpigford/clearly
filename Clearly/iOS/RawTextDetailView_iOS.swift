import SwiftUI
import ClearlyCore

struct RawTextDetailView_iOS: View {
    @Environment(VaultSession.self) private var vault
    @Environment(\.scenePhase) private var scenePhase

    let file: VaultFile

    @State private var document = IOSDocumentSession()
    @State private var viewMode: ViewMode = .edit
    @StateObject private var backlinksState = BacklinksState()
    @StateObject private var outlineState = OutlineState()
    @State private var showBacklinks = false
    @State private var showOutline = false

    var body: some View {
        VStack(spacing: 0) {
            if document.hasConflict { conflictBanner }
            content
        }
        .navigationTitle(document.isDirty ? "• \(file.name)" : file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View mode", selection: $viewMode) {
                    Text("Edit").tag(ViewMode.edit)
                    Text("Preview").tag(ViewMode.preview)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showOutline = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .accessibilityLabel("Outline")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBacklinks = true
                } label: {
                    Image(systemName: "link")
                }
                .accessibilityLabel("Backlinks")
            }
        }
        .background {
            QuickSwitcherShortcuts()
        }
        .task(id: file.id) {
            await document.open(file, via: vault)
            if document.errorMessage == nil {
                vault.markRecent(file)
                outlineState.parseHeadings(from: document.text)
                refreshBacklinks()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                Task { await document.flush() }
            }
        }
        .onChange(of: document.text) { _, newText in
            outlineState.parseHeadings(from: newText)
        }
        .onChange(of: vault.indexProgress) { _, newValue in
            if newValue == nil { refreshBacklinks() }
        }
        .onDisappear {
            Task { await document.close() }
        }
        .sheet(isPresented: $showBacklinks) {
            BacklinksSheet_iOS(backlinksState: backlinksState)
                .environment(vault)
        }
        .sheet(isPresented: $showOutline) {
            OutlineSheet_iOS(outlineState: outlineState, onJump: jumpToHeading)
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
            switch viewMode {
            case .edit:
                EditorView_iOS(
                    text: Binding(
                        get: { document.text },
                        set: { document.text = $0 }
                    ),
                    outlineState: outlineState
                )
            case .preview:
                PreviewView_iOS(
                    markdown: document.text,
                    fileURL: file.url,
                    onWikiLinkClicked: handleWikiLink,
                    onTaskToggle: handleTaskToggle
                )
            }
        }
    }

    private func refreshBacklinks() {
        let indexes = [vault.currentIndex].compactMap { $0 }
        backlinksState.update(for: file.url, using: indexes)
    }

    private func jumpToHeading(_ heading: HeadingItem) {
        viewMode = .edit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            outlineState.scrollToRange?(heading.range)
        }
    }

    private func handleWikiLink(_ target: String) {
        Task {
            do {
                let file = try await vault.openOrCreate(name: target)
                vault.navigationPath.append(file)
            } catch {
                DiagnosticLog.log("Wiki-link open/create failed for \(target): \(error)")
            }
        }
    }

    private func handleTaskToggle(_ line: Int, _ checked: Bool) {
        var lines = document.text.components(separatedBy: "\n")
        let idx = line - 1
        guard idx >= 0, idx < lines.count else { return }
        if checked {
            lines[idx] = lines[idx]
                .replacingOccurrences(of: "- [ ]", with: "- [x]")
                .replacingOccurrences(of: "* [ ]", with: "* [x]")
                .replacingOccurrences(of: "+ [ ]", with: "+ [x]")
        } else {
            lines[idx] = lines[idx]
                .replacingOccurrences(of: "- [x]", with: "- [ ]")
                .replacingOccurrences(of: "- [X]", with: "- [ ]")
                .replacingOccurrences(of: "* [x]", with: "* [ ]")
                .replacingOccurrences(of: "* [X]", with: "* [ ]")
                .replacingOccurrences(of: "+ [x]", with: "+ [ ]")
                .replacingOccurrences(of: "+ [X]", with: "+ [ ]")
        }
        document.text = lines.joined(separator: "\n")
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
