import SwiftUI
import ClearlyCore

/// Root view for the native macOS shell (Phase M2 — scaffold).
///
/// Three-column `NavigationSplitView` that mirrors the iPad shell in
/// `IPadRootView.swift`. Populated progressively in M3 (folder sidebar),
/// M4 (notes list), and M5 (detail column + toolbar). This file intentionally
/// contains placeholder content — functional feature code lands in subsequent
/// phases, not here.
struct MacRootView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FoldersColumnPlaceholder()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            NotesListColumnPlaceholder()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            DetailColumnPlaceholder()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct FoldersColumnPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Folders",
            systemImage: "folder",
            description: Text("Sidebar arrives in Phase M3.")
        )
    }
}

private struct NotesListColumnPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Notes",
            systemImage: "doc.text",
            description: Text("Notes list arrives in Phase M4.")
        )
    }
}

private struct DetailColumnPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Editor",
            systemImage: "square.and.pencil",
            description: Text("Editor + toolbar arrive in Phase M5.")
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {} label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .disabled(true)
            }
        }
    }
}
