import SwiftUI
import ClearlyCore

/// Shows every ATX / Setext heading in the current document. Tapping a row
/// dismisses the sheet and calls `outlineState.scrollToRange?(heading.range)`;
/// the live editor coordinator owns that closure (see `EditorView_iOS`).
struct OutlineSheet_iOS: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var outlineState: OutlineState
    var onJump: ((HeadingItem) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if outlineState.headings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No headings")
                            .font(.headline)
                        Text("Add `# Heading` lines to build an outline.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(outlineState.headings) { heading in
                        Button { jump(to: heading) } label: {
                            Text(heading.title)
                                .font(font(for: heading.level))
                                .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.leading, CGFloat(heading.level - 1) * 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 15, weight: .semibold)
        case 2: return .system(size: 14, weight: .medium)
        default: return .system(size: 13, weight: .regular)
        }
    }

    private func jump(to heading: HeadingItem) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let onJump {
                onJump(heading)
            } else {
                outlineState.scrollToRange?(heading.range)
            }
        }
    }
}
