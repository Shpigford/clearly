import SwiftUI
import ClearlyCore

struct ConflictBannerView: View {
    let outcome: ConflictResolver.Outcome
    let onViewDiff: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This note has an offline conflict")
                    .font(.callout)
                Text("Conflict saved as \(outcome.siblingURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("View diff", action: onViewDiff)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
    }
}
