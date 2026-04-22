#if os(iOS)
import SwiftUI
import ClearlyCore

/// Long-press context-menu preview card for a vault file. Loads the file's
/// first ~600 chars off-main on appear and renders them in the editor's
/// monospaced font for a "this is what you'd see" feel. Placeholder iCloud
/// files surface a download hint instead of a blank card. The card is sized
/// for iPad pointer/touch — large enough to read, small enough to feel like
/// a peek, not a full sheet.
///
/// Used by both the iPhone `FileListView_iOS` rows and the iPad
/// `IPadRootView` rich rows. Frontmatter is dropped from the snippet via
/// `stripFrontmatter(_:)` (in this file) so the preview shows actual content.
struct FileRowPreviewCard: View {
    let file: VaultFile
    @State private var snippet: String?
    @State private var didLoad: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: file.isPlaceholder ? "icloud.and.arrow.down" : "doc.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(file.isPlaceholder ? .secondary : Theme.accentColorSwiftUI)
                Text(displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            Group {
                if file.isPlaceholder {
                    placeholderHint
                } else if let snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(Theme.editorFontSwiftUI)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                } else if didLoad {
                    Text("Empty note")
                        .font(Theme.Typography.welcomeSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 320, height: 240, alignment: .topLeading)
        .background(Theme.backgroundColorSwiftUI)
        .task {
            guard !file.isPlaceholder else {
                didLoad = true
                return
            }
            let url = file.url
            let loaded: String? = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                guard let text = String(data: data, encoding: .utf8) else { return nil }
                let trimmed = stripFrontmatter(text)
                let cap = 600
                if trimmed.count <= cap { return trimmed }
                let endIdx = trimmed.index(trimmed.startIndex, offsetBy: cap)
                return String(trimmed[..<endIdx]) + "…"
            }.value
            await MainActor.run {
                snippet = loaded
                didLoad = true
            }
        }
    }

    private var displayTitle: String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        if FileNode.markdownExtensions.contains(ext) {
            return (file.name as NSString).deletingPathExtension
        }
        return file.name
    }

    private var placeholderHint: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Not yet downloaded")
                .font(Theme.Typography.welcomeSubtitle)
                .foregroundStyle(.secondary)
            Text("Open this note to download from iCloud.")
                .font(Theme.Typography.findCount)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Drop a leading YAML frontmatter block (between two `---` lines) so file
/// previews show actual content instead of metadata. Mirrors the pattern in
/// `ClearlyCore.FrontmatterSupport` without pulling in its full parsing.
/// File-private to this module; both `FileRowPreviewCard` and the iPad
/// `RichFileRow` use it.
func stripFrontmatter(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var endIdx: Int?
    for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
        endIdx = i
        break
    }
    guard let endIdx else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let body = lines[(endIdx + 1)...].joined(separator: "\n")
    return body.trimmingCharacters(in: .whitespacesAndNewlines)
}
#endif
