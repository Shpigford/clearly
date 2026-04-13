import SwiftUI

struct OutlineView: View {
    @ObservedObject var outlineState: OutlineState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OUTLINE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(1.5)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? Theme.separatorOpacityDark : Theme.separatorOpacity))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if outlineState.headings.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text("Add headings with # to build an outline")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(outlineState.headings) { heading in
                            HeadingRow(heading: heading) {
                                outlineState.scrollToRange?(heading.range)
                                outlineState.scrollToPreviewAnchor?(heading.previewAnchor)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.outlinePanelBackgroundSwiftUI)
    }
}

private struct HeadingRow: View {
    let heading: HeadingItem
    let onTap: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var font: Font {
        switch heading.level {
        case 1: return .system(size: 13, weight: .semibold)
        case 2: return .system(size: 12, weight: .medium)
        default: return .system(size: 12, weight: .regular)
        }
    }

    private var indent: CGFloat {
        CGFloat(heading.level - 1) * 14
    }

    var body: some View {
        Button(action: onTap) {
            Text(heading.title)
                .font(font)
                .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12 + indent)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
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
