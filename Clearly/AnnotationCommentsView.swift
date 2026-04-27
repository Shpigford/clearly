import SwiftUI
import ClearlyCore

struct AnnotationCommentsView: View {
    @ObservedObject var commentsState: AnnotationCommentsState
    @ObservedObject var outlineState: OutlineState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("COMMENTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(1.5)

                if !commentsState.comments.isEmpty {
                    Text("\(commentsState.comments.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? Theme.separatorOpacityDark : Theme.separatorOpacity))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if commentsState.comments.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("No comments")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text("Add annotations to selected text")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    AnnotationCommentRows(comments: commentsState.comments) { comment in
                        outlineState.scrollToRange?(comment.sourceRange)
                        outlineState.scrollToPreviewAnchor?(comment.previewAnchor)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.outlinePanelBackgroundSwiftUI)
    }
}

private struct AnnotationCommentRows: View {
    let comments: [AnnotationCommentItem]
    let onSelect: (AnnotationCommentItem) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(comments.indices, id: \.self) { index in
                let comment = comments[index]
                AnnotationCommentRow(comment: comment) {
                    onSelect(comment)
                }
            }
        }
    }
}

private struct AnnotationCommentRow: View {
    let comment: AnnotationCommentItem
    let onTap: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                Text(comment.highlightedText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(comment.comment ?? "No comment text")
                    .font(.system(size: 11))
                    .foregroundStyle(comment.comment == nil ? .tertiary : .secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let metadata {
                    Text(metadata)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

    private var metadata: String? {
        let parts = [comment.author, comment.date, comment.status]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
