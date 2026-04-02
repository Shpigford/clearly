import SwiftUI

struct OutlineView: View {
    @ObservedObject var outlineState: OutlineState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OUTLINE")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .tracking(1)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if outlineState.headings.isEmpty {
                Spacer()
                Text("No headings")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
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
        .frame(width: 200)
    }
}

private struct HeadingRow: View {
    let heading: HeadingItem
    let onTap: () -> Void
    @State private var isHovered = false

    private var font: Font {
        switch heading.level {
        case 1: return .system(size: 13, weight: .semibold)
        case 2: return .system(size: 12, weight: .medium)
        default: return .system(size: 11, weight: .regular)
        }
    }

    private var indent: CGFloat {
        CGFloat(heading.level - 1) * 12
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
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
