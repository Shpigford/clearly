import SwiftUI
import ClearlyCore

/// Multi-document tab bar — sits above the editor inside the detail column.
/// Matches Apple Notes' muted aesthetic: rounded-rect selection fill on the
/// active tab, dirty-dot on unsaved docs, hover-to-reveal close button.
/// Hidden when fewer than two documents are open to match the iPad model.
struct MacTabBar: View {
    @Bindable var workspace: WorkspaceManager

    var body: some View {
        if workspace.openDocuments.count >= 2 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.openDocuments) { doc in
                        let label = workspace.tabLabel(for: doc)
                        MacTabRow(
                            doc: doc,
                            parentQualifier: label.parent,
                            filename: label.filename,
                            isActive: doc.id == workspace.activeDocumentID,
                            isHovered: doc.id == workspace.hoveredTabID,
                            onSelect: { workspace.switchToDocument(doc.id) },
                            onClose: { workspace.closeDocument(doc.id) },
                            onHover: { isInside in
                                workspace.hoveredTabID = isInside ? doc.id : nil
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 32)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}

private struct MacTabRow: View {
    let doc: OpenDocument
    let parentQualifier: String?
    let filename: String
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if doc.isDirty {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
            }
            HStack(spacing: 0) {
                if let parent = parentQualifier {
                    Text("\(parent)/")
                        .foregroundStyle(.tertiary)
                }
                Text(filename)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .font(.subheadline)
            .lineLimit(1)
            if isHovered || isActive {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { onHover($0) }
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Close Tab") { onClose() }
        }
    }
}
