import SwiftUI

struct ScratchpadShellView: View {
    @Environment(ScratchpadManager.self) private var manager
    @Environment(ScratchpadStore.self) private var store
    @Environment(ScratchpadDeleteUndoController.self) private var undo

    @State private var text: String = ""
    @State private var loadedNoteID: ScratchpadNote.ID?
    @AppStorage("editorFontSize") private var fontSize: Double = 12

    var body: some View {
        @Bindable var bindableManager = manager
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 28)
                ScratchpadEditorView(
                    text: $text,
                    fontSize: CGFloat(fontSize),
                    onSave: { manager.saveCurrentAsDocument() },
                    onTextChange: { newText in
                        guard let note = manager.currentNote else { return }
                        store.write(text: newText, to: note.url)
                    }
                )
            }

            ScratchpadTitlebarBar()
                .frame(height: 28)
                .frame(maxWidth: .infinity)

            VStack {
                Spacer()
                ScratchpadDeleteUndoToast()
                    .animation(.easeOut(duration: 0.18), value: undo.pendingToken)
            }

            VStack(spacing: 0) {
                Button("") { manager.createAndShowNew() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("") { bindableManager.historyPopoverShown.toggle() }
                    .keyboardShortcut("p", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 360, minHeight: 280)
        .onAppear(perform: syncText)
        .onChange(of: manager.currentNoteID) { _, _ in syncText() }
    }

    private func syncText() {
        guard let note = manager.currentNote else {
            text = ""
            loadedNoteID = nil
            return
        }
        if loadedNoteID == note.id { return }
        loadedNoteID = note.id
        text = store.loadText(for: note)
    }
}

// MARK: - Toolbar buttons

struct ScratchpadTitleMenuButton: View {
    @Environment(ScratchpadManager.self) private var manager
    @Environment(ScratchpadStore.self) private var store

    var body: some View {
        @Bindable var bindable = manager
        Button {
            bindable.historyPopoverShown.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Browse scratchpads (⌘P)")
        .popover(isPresented: $bindable.historyPopoverShown, arrowEdge: .bottom) {
            ScratchpadHistoryPicker {
                bindable.historyPopoverShown = false
            }
            .environment(manager)
            .environment(store)
        }
    }

    private var displayTitle: String {
        manager.currentNote?.title ?? "Scratchpad"
    }
}

struct ScratchpadNewNoteButton: View {
    @Environment(ScratchpadManager.self) private var manager

    var body: some View {
        Button {
            manager.createAndShowNew()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .regular))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("New Scratchpad (⌘N)")
    }
}

// MARK: - Custom titlebar overlay

struct ScratchpadTitlebarBar: View {
    var body: some View {
        ZStack {
            ScratchpadTitleMenuButton()
                .padding(.horizontal, 72)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ScratchpadNewNoteButton()
                    .padding(.trailing, 12)
            }
        }
    }
}

