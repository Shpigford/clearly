import SwiftUI
import ClearlyCore

struct BacklinksView: View {
    @ObservedObject var backlinksState: BacklinksState
    var onNavigate: (Backlink) -> Void
    var onLink: (Backlink) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var totalCount: Int {
        backlinksState.backlinks.count + backlinksState.unlinkedMentions.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text("BACKLINKS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(1.5)
                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? Theme.separatorOpacityDark : Theme.separatorOpacity))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if backlinksState.backlinks.isEmpty && backlinksState.unlinkedMentions.isEmpty {
                Text("No other documents link to this file")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Linked mentions
                        if !backlinksState.backlinks.isEmpty {
                            ForEach(backlinksState.backlinks) { backlink in
                                BacklinkRow(backlink: backlink) {
                                    onNavigate(backlink)
                                }
                            }
                        }

                        // Unlinked mentions
                        if !backlinksState.unlinkedMentions.isEmpty {
                            DisclosureGroup {
                                ForEach(backlinksState.unlinkedMentions) { backlink in
                                    BacklinkRow(backlink: backlink, showLinkButton: true, onTap: {
                                        onNavigate(backlink)
                                    }, onLink: {
                                        onLink(backlink)
                                    })
                                }
                            } label: {
                                Text("Unlinked (\(backlinksState.unlinkedMentions.count))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundColorSwiftUI)
    }
}

private struct BacklinkRow: View {
    let backlink: Backlink
    var showLinkButton: Bool = false
    let onTap: () -> Void
    var onLink: (() -> Void)? = nil
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(backlink.sourceFilename)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !backlink.contextLine.isEmpty {
                        Text(backlink.contextLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if showLinkButton, let onLink {
                Button(action: onLink) {
                    Text("Link")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered
                    ? Color.primary.opacity(colorScheme == .dark ? Theme.hoverOpacityDark - 0.03 : 0.05)
                    : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) {
                isHovered = hovering
            }
        }
    }
}
