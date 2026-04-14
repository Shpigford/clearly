import SwiftUI

struct TabBarView: View {
    @Bindable var workspace: WorkspaceManager
    @Environment(\.colorScheme) private var colorScheme

    private var tabBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor).opacity(0.6)
            : Color.primary.opacity(0.04)
    }

    var body: some View {
        if workspace.openDocuments.count >= 2 {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(Array(workspace.openDocuments.enumerated()), id: \.element.id) { index, doc in
                            TabItemView(
                                doc: doc,
                                isActive: doc.id == workspace.activeDocumentID,
                                isLast: index == workspace.openDocuments.count - 1,
                                onSelect: { workspace.switchToDocument(doc.id) },
                                onClose: { workspace.closeDocument(doc.id) }
                            )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
                .frame(height: 38)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity)
            .background(tabBackground)
        }
    }
}

private struct TabItemView: View {
    let doc: OpenDocument
    let isActive: Bool
    let isLast: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 5) {
                    Text(displayName)
                        .font(.system(size: 12, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Close / dirty indicator
            Group {
                if doc.isDirty && !(isActive || isHovering) {
                    Circle()
                        .fill(Color.primary.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .padding(.leading, 6)
                } else if isActive || isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                } else {
                    Spacer()
                        .frame(width: 8)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                    ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                    : Color.clear)
                .shadow(color: isActive ? Color.black.opacity(colorScheme == .dark ? 0.3 : 0.06) : .clear, radius: 1, y: 0.5)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var displayName: String {
        if let url = doc.fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return doc.displayName
    }
}
