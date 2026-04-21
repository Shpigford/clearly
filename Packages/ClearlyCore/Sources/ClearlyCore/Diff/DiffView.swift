import SwiftUI

public struct DiffView: View {
    public let leftTitle: String
    public let leftText: String
    public let rightTitle: String
    public let rightText: String
    public let footer: String?
    public let onDismiss: () -> Void

    public init(
        leftTitle: String,
        leftText: String,
        rightTitle: String,
        rightText: String,
        footer: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.leftTitle = leftTitle
        self.leftText = leftText
        self.rightTitle = rightTitle
        self.rightText = rightText
        self.footer = footer
        self.onDismiss = onDismiss
    }

    private enum Side: Hashable { case left, right }

    @State private var rows: [LineDiff.Row] = []
    @State private var isTooLarge = false
    @State private var didCompute = false
    @State private var selectedSide: Side = .left

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public var body: some View {
        NavigationStack {
            Group {
                if !didCompute {
                    ProgressView("Computing diff…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isTooLarge {
                    tooLargeView
                } else if isCompact {
                    compactLayout
                } else {
                    wideLayout
                }
            }
            .navigationTitle("Conflict")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .task { computeDiff() }
    }

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private func computeDiff() {
        do {
            rows = try LineDiff.rows(left: leftText, right: rightText)
            isTooLarge = false
        } catch {
            rows = []
            isTooLarge = true
        }
        didCompute = true
    }

    // MARK: - Wide (side-by-side)

    private var wideLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                columnHeader(leftTitle)
                columnHeader(rightTitle)
            }
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 1) {
                            diffCell(text: row.left, op: row.op, side: .left)
                            diffCell(text: row.right, op: row.op, side: .right)
                        }
                    }
                }
            }
            footerView
        }
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func diffCell(text: String?, op: LineDiff.Op, side: Side) -> some View {
        let background: Color = {
            switch (op, side) {
            case (.removed, .left): return .red.opacity(0.18)
            case (.added, .right): return .green.opacity(0.18)
            default: return .clear
            }
        }()
        Text(text ?? " ")
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(background)
    }

    // MARK: - Compact (tab toggle)

    private var compactLayout: some View {
        VStack(spacing: 0) {
            Picker("Version", selection: $selectedSide) {
                Text(leftTitle).tag(Side.left)
                Text(rightTitle).tag(Side.right)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        compactRow(row)
                    }
                }
            }
            footerView
        }
    }

    @ViewBuilder
    private func compactRow(_ row: LineDiff.Row) -> some View {
        let (line, background): (String?, Color) = {
            switch selectedSide {
            case .left:
                return (row.left, row.op == .removed ? .red.opacity(0.18) : .clear)
            case .right:
                return (row.right, row.op == .added ? .green.opacity(0.18) : .clear)
            }
        }()
        if let line {
            Text(line)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(background)
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var footerView: some View {
        if let footer {
            Divider()
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private var tooLargeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("This note is too large to diff in-app.")
                .font(.headline)
            Text("Open both files side by side to compare them manually.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            footerView
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
