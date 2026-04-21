#if os(iOS)
import SwiftUI
import ClearlyCore

/// Horizontal tab strip rendered above the iPad detail column's editor.
/// Scrolls horizontally when tabs overflow; ScrollViewReader keeps the
/// active tab in view on activation. Mirrors `TabBarView.swift`'s
/// visual language while using iOS-native surfaces.
struct IPadTabBar: View {
    let controller: IPadTabController

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(controller.tabs) { tab in
                            IPadTabItem(
                                tab: tab,
                                isActive: tab.id == controller.activeTabID,
                                onSelect: { controller.activate(id: tab.id) },
                                onClose: { controller.closeTab(id: tab.id) }
                            )
                            .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: controller.activeTabID) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
            .frame(height: 44)

            Divider()
        }
        .background(Color(.secondarySystemBackground))
    }
}

private struct IPadTabItem: View {
    let tab: IPadTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    indicator
                    Text(displayName)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(displayName)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Color(.systemBackground) : Color.clear)
                .shadow(color: isActive ? Color.black.opacity(0.08) : .clear, radius: 1, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isActive ? Color.primary.opacity(0.08) : .clear, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        if tab.session.conflictOutcome != nil || tab.session.wasDeletedRemotely {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        } else if tab.session.isDirty {
            Circle()
                .fill(Color.primary.opacity(isActive ? 0.6 : 0.4))
                .frame(width: 6, height: 6)
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var displayName: String {
        let name = tab.session.file?.name ?? tab.file.name
        let ext = (name as NSString).pathExtension.lowercased()
        if FileNode.markdownExtensions.contains(ext) {
            return (name as NSString).deletingPathExtension
        }
        return name
    }
}
#endif
